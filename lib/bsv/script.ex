defmodule BSV.Script do
  @moduledoc """
  Module for the construction, parsing and serialization of transactions to and
  from binary data.

  ## Examples

      iex> %BSV.Script{}
      ...> |> BSV.Script.push(:OP_FALSE)
      ...> |> BSV.Script.push(:OP_RETURN)
      ...> |> BSV.Script.push("hello world")
      ...> |> BSV.Script.serialize(encoding: :hex)
      "006a68656c6c6f20776f726c64"

      iex> "006a68656c6c6f20776f726c64"
      ...> |> BSV.Script.parse(encoding: :hex)
      %BSV.Script{
        chunks: [:OP_FALSE, :OP_RETURN, "hello world"]
      }
  """

  require Logger

  alias BSV.Script.OpCode
  alias BSV.Util

  defstruct chunks: [], coinbase: nil

  @typedoc "Bitcoin Script"
  @type t :: %__MODULE__{
          chunks: list,
          coinbase: binary | nil
        }

  @doc """
  Parses the given binary into a transaction script.

  ## Options

  The accepted options are:

  * `:encoding` - Optionally decode the binary with either the `:base64` or `:hex` encoding scheme.

  ## Examples

      iex> "76a9146afc0d6bb578282ac0f6ad5c5af2294c1971210888ac"
      ...> |> BSV.Script.parse(encoding: :hex)
      %BSV.Script{
        chunks: [
          :OP_DUP,
          :OP_HASH160,
          <<106, 252, 13, 107, 181, 120, 40, 42, 192, 246, 173, 92, 90, 242, 41, 76, 25, 113, 33, 8>>,
          :OP_EQUALVERIFY,
          :OP_CHECKSIG
        ]
      }
  """
  @spec parse(binary, keyword) :: __MODULE__.t()
  def parse(data, options \\ []) do
    encoding = Keyword.get(options, :encoding)

    Util.decode(data, encoding)
    |> parse_chunks([])
  end

  defp parse_chunks(<<>>, chunks),
    do: struct(__MODULE__, chunks: Enum.reverse(chunks))

  defp parse_chunks(<<op::integer, data::binary>>, chunks)
       when op > 0 and op < 76 do
    size = chunk_size(data, op)
    <<chunk::bytes-size(size), data::binary>> = data
    parse_chunks(data, [chunk | chunks])
  end

  defp parse_chunks(<<76, size::integer, data::binary>>, chunks) do
    size = chunk_size(data, size)
    <<chunk::bytes-size(size), data::binary>> = data
    parse_chunks(data, [chunk | chunks])
  end

  defp parse_chunks(<<77, size::little-16, data::binary>>, chunks) do
    size = chunk_size(data, size)
    <<chunk::bytes-size(size), data::binary>> = data
    parse_chunks(data, [chunk | chunks])
  end

  defp parse_chunks(<<78, size::little-32, data::binary>>, chunks) do
    size = chunk_size(data, size)
    <<chunk::bytes-size(size), data::binary>> = data
    parse_chunks(data, [chunk | chunks])
  end

  defp parse_chunks(<<op::integer, data::binary>>, chunks) do
    {opcode, _opnum} = OpCode.get(op)

    if :OP_RETURN == opcode do
      parse_chunks(<<>>, [data, opcode | chunks])
    else
      parse_chunks(data, [opcode | chunks])
    end
  end

  defp chunk_size(data, size) do
    data_size = byte_size(data)

    if size > data_size do
      Logger.warn(
        "Expect to get #{size} byte(s), but the actual data size is #{data_size} byte(s)."
      )

      data_size
    else
      size
    end
  end

  @doc """
  Pushes a chunk into the given transaction script. The chunk can be any binary
  value or OP code.

  ## Examples

      iex> %BSV.Script{}
      ...> |> BSV.Script.push(:OP_FALSE)
      ...> |> BSV.Script.push(:OP_RETURN)
      ...> |> BSV.Script.push("Hello world")
      %BSV.Script{
        chunks: [
          :OP_FALSE,
          :OP_RETURN,
          "Hello world"
        ]
      }
  """
  @spec push(__MODULE__.t(), binary | atom) :: __MODULE__.t()
  def push(%__MODULE__{} = script, data)
      when is_atom(data) or is_integer(data) do
    with {opcode, _opnum} <- OpCode.get(data) do
      push_chunk(script, opcode)
    else
      _err -> raise "Invalid OP Code"
    end
  end

  def push(%__MODULE__{} = script, data) when is_binary(data),
    do: push_chunk(script, data)

  defp push_chunk(%__MODULE__{} = script, data) do
    chunks = Enum.concat(script.chunks, [data])
    Map.put(script, :chunks, chunks)
  end

  @doc """
  Serialises the given script into a binary.

  ## Options

  The accepted options are:

  * `:encode` - Optionally encode the returned binary with either the `:base64` or `:hex` encoding scheme.

  ## Examples

      iex> %BSV.Script{}
      ...> |> BSV.Script.push(:OP_DUP)
      ...> |> BSV.Script.push(:OP_HASH160)
      ...> |> BSV.Script.push(<<106, 252, 13, 107, 181, 120, 40, 42, 192, 246, 173, 92, 90, 242, 41, 76, 25, 113, 33, 8>>)
      ...> |> BSV.Script.push(:OP_EQUALVERIFY)
      ...> |> BSV.Script.push(:OP_CHECKSIG)
      ...> |> BSV.Script.serialize(encoding: :hex)
      "76a9146afc0d6bb578282ac0f6ad5c5af2294c1971210888ac"
  """
  @spec serialize(__MODULE__.t(), keyword) :: binary
  def serialize(script, options \\ [])

  def serialize(%__MODULE__{coinbase: nil} = script, options) do
    encoding = Keyword.get(options, :encoding)

    serialize_chunks(script.chunks, <<>>)
    |> Util.encode(encoding)
  end

  def serialize(%__MODULE__{coinbase: coinbase, chunks: []}, options) do
    encoding = Keyword.get(options, :encoding)
    Util.encode(coinbase, encoding)
  end

  defp serialize_chunks([], data), do: data

  defp serialize_chunks([chunk | chunks], data) when is_atom(chunk) do
    {opcode, opnum} = OpCode.get(chunk)

    if :OP_RETURN == opcode and length(chunks) == 1 do
      [rest | _] = chunks
      serialize_chunks([], <<data::binary, opnum::integer, rest::binary>>)
    else
      serialize_chunks(chunks, <<data::binary, opnum::integer>>)
    end
  end

  defp serialize_chunks([chunk | chunks], data) when is_binary(chunk) do
    suffix =
      case byte_size(chunk) do
        op when op > 0 and op < 76 ->
          <<op::integer, chunk::binary>>

        len when len < 0x100 ->
          <<76::integer, len::integer, chunk::binary>>

        len when len < 0x10000 ->
          <<77::integer, len::little-16, chunk::binary>>

        len when len < 0x100000000 ->
          <<78::integer, len::little-32, chunk::binary>>

        op ->
          <<op::integer>>
      end

    serialize_chunks(chunks, data <> suffix)
  end

  @doc """
  Gets a coinbase script.

  ## Examples

    iex> Script.get_coinbase("keep calm and BSV on")
    %Script{coinbase: "keep calm and BSV on", chunks: []}
  """
  @spec get_coinbase(binary) :: __MODULE__.t()
  def get_coinbase(data), do: %__MODULE__{coinbase: data, chunks: []}

  @doc """
  Gets whether this is a coinbase script.

  ## Examples

    iex> Script.get_coinbase("keep calm and BSV on") |> Script.is_coinbase()
    true

    iex> %Script{chunks: [:OP_1]} |> Script.is_coinbase()
    false

  """
  @spec is_coinbase(__MODULE__.t()) :: boolean
  def is_coinbase(%__MODULE__{coinbase: nil}), do: false
  def is_coinbase(%__MODULE__{coinbase: data, chunks: []}) when data !== nil, do: true
end
