defmodule BSV.Transaction.Input do
  @moduledoc """
  Module for parsing and serialising transaction inputs.
  """
  alias BSV.Script
  alias BSV.Transaction.Output
  alias BSV.Util
  alias BSV.Util.VarBin

  defstruct output_txid: nil,
            output_index: 0,
            script: nil,
            sequence: 0,
            utxo: nil

  @typedoc "Transaction input"
  @type t :: %__MODULE__{
    output_txid: String.t,
    output_index: integer,
    script: binary,
    sequence: integer,
    utxo: Output.t
  }

  @max_sequence 0xFFFFFFFF


  @doc """
  Parse the given binary into a transaction input. Returns a tuple containing
  the transaction input and the remaining binary data.

  ## Options

  The accepted options are:

  * `:encoding` - Optionally decode the binary with either the `:base64` or `:hex` encoding scheme.

  ## Examples

      BSV.Transaction.Input.parse(data)
      {%BSV.Trasaction.Input{}, ""}
  """
  @spec parse(binary, keyword) :: {__MODULE__.t, binary}
  def parse(data, options \\ []) do
    encoding = Keyword.get(options, :encoding)

    <<txid::bytes-32, index::little-32, data::binary>> = data
    |> Util.decode(encoding)
    {script, data} = VarBin.parse_bin(data)
    <<sequence::little-32, data::binary>> = data

    {struct(__MODULE__, [
      output_txid: txid |> Util.reverse_bin |> Util.encode(:hex),
      output_index: index,
      script: Script.parse(script),
      sequence: sequence
    ]), data}
  end


  @doc """
  Serialises the given transaction input struct into a binary.

  ## Options

  The accepted options are:

  * `:encode` - Optionally encode the returned binary with either the `:base64` or `:hex` encoding scheme.

  ## Examples

      BSV.Transaction.Input.serialize(input)
      <<binary>>
  """
  @spec serialize(__MODULE__.t, keyword) :: binary
  def serialize(%__MODULE__{} = input, options \\ []) do
    encoding = Keyword.get(options, :encoding)

    txid = input.output_txid
    |> Util.decode(:hex)
    |> Util.reverse_bin
    script = input.script
    |> Script.serialize
    |> VarBin.serialize_bin

    <<
      txid::binary,
      input.output_index::little-32,
      script::binary,
      input.sequence::little-32
    >>
    |> Util.encode(encoding)
  end
  
end