defmodule DBF.Memo do
  @moduledoc false

  alias DBF.Error
  alias DBF.Resource

  @header_bytes 512

  @enforce_keys [:family, :block_size]
  defstruct [:family, :block_size]

  @type family :: :dbt_iii | :dbt_iv
  @type t :: %__MODULE__{family: family(), block_size: pos_integer()}

  @spec initialize(Resource.t(), family()) :: {:ok, t()} | {:error, Error.t()}
  def initialize(resource, family) when family in [:dbt_iii, :dbt_iv] do
    case Resource.read_exact(resource, :memo, 0, @header_bytes) do
      {:ok,
       <<_next_block::little-unsigned-integer-size(32),
         block_size::little-unsigned-integer-size(16), _rest::binary>>} ->
        {:ok,
         %__MODULE__{
           family: family,
           block_size: if(block_size > 0, do: block_size, else: 512)
         }}

      {:error, %Error{} = error} ->
        {:error, %Error{error | reason: :invalid_memo}}
    end
  end

  @spec get_block(Resource.t(), t() | nil, non_neg_integer()) :: binary() | {:error, Error.t()}
  def get_block(_resource, nil, _block_number) do
    {:error, Error.new(:missing_memo_file, :not_acquired, %{source: :memo})}
  end

  def get_block(
        resource,
        %__MODULE__{family: :dbt_iii, block_size: block_size},
        block_number
      ) do
    offset = block_number * block_size

    case Resource.read_exact(resource, :memo, offset, 512) do
      {:ok, raw_data} -> clean_text(raw_data)
      {:error, %Error{} = error} -> {:error, %Error{error | reason: :invalid_memo}}
    end
  end

  def get_block(resource, %__MODULE__{family: :dbt_iv, block_size: block_size}, block_number) do
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
