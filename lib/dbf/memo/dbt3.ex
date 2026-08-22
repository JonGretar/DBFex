defmodule DBF.Memo.DBT3 do
  @moduledoc false

  alias DBF.Error
  alias DBF.Memo
  alias DBF.Resource

  @header_bytes 512

  @spec initialize(Resource.t()) :: {:ok, Memo.t()} | {:error, Error.t()}
  def initialize(resource) do
    case Resource.read_exact(resource, :memo, 0, @header_bytes) do
      {:ok,
       <<_next_block::little-unsigned-integer-size(32),
         block_size::little-unsigned-integer-size(16), _rest::binary>>} ->
        {:ok,
         %Memo{
           family: :dbt_iii,
           block_size: if(block_size > 0, do: block_size, else: 512)
         }}

      {:error, %Error{} = error} ->
        {:error, %Error{error | reason: :invalid_memo}}
    end
  end

  @spec get_block(Resource.t(), Memo.t(), non_neg_integer()) :: binary() | {:error, Error.t()}
  def get_block(resource, %Memo{block_size: block_size}, block_number) do
    offset = block_number * block_size

    case Resource.read_exact(resource, :memo, offset, 512) do
      {:ok, raw_data} -> clean_text(raw_data)
      {:error, %Error{} = error} -> {:error, %Error{error | reason: :invalid_memo}}
    end
  end

  defp clean_text(raw_data) do
    raw_data
    |> :binary.replace(<<31>>, <<>>, [:global])
    |> String.trim()
  end
end
