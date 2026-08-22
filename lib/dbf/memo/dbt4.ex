defmodule DBF.Memo.DBT4 do
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
           family: :dbt_iv,
           block_size: if(block_size > 0, do: block_size, else: 512)
         }}

      {:error, %Error{} = error} ->
        {:error, %Error{error | reason: :invalid_memo}}
    end
  end

  @spec get_block(Resource.t(), Memo.t(), non_neg_integer()) :: binary() | {:error, Error.t()}
  def get_block(resource, %Memo{block_size: block_size}, block_number) do
    offset = block_number * block_size

    with {:ok, <<_type::binary-size(4), length::little-unsigned-integer-size(32)>>} <-
           Resource.read_exact(resource, :memo, offset, 8),
         {:ok, raw_data} <- Resource.read_exact(resource, :memo, offset + 8, length) do
      clean_text(raw_data)
    else
      {:error, %Error{} = error} -> {:error, %Error{error | reason: :invalid_memo}}
    end
  end

  defp clean_text(raw_data) do
    raw_data
    |> :binary.replace(<<31>>, <<>>, [:global])
    |> String.trim()
  end
end
