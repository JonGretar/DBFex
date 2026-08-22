defmodule DBF.Memo do
  @moduledoc false

  alias DBF.Error
  alias DBF.Memo.DBT3
  alias DBF.Memo.DBT4
  alias DBF.Resource

  @enforce_keys [:family, :block_size]
  defstruct [:family, :block_size]

  @type family :: :dbt_iii | :dbt_iv
  @type t :: %__MODULE__{family: family(), block_size: pos_integer()}

  @spec initialize(Resource.t(), family()) :: {:ok, t()} | {:error, Error.t()}
  def initialize(resource, :dbt_iii), do: DBT3.initialize(resource)
  def initialize(resource, :dbt_iv), do: DBT4.initialize(resource)

  @spec get_block(Resource.t(), t() | nil, non_neg_integer()) :: binary() | {:error, Error.t()}
  def get_block(_resource, nil, _block_number) do
    {:error, Error.new(:missing_memo_file, :not_acquired, %{source: :memo})}
  end

  def get_block(resource, %__MODULE__{family: :dbt_iii} = memo, block_number) do
    DBT3.get_block(resource, memo, block_number)
  end

  def get_block(resource, %__MODULE__{family: :dbt_iv} = memo, block_number) do
    DBT4.get_block(resource, memo, block_number)
  end
end
