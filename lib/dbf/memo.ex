defmodule DBF.Memo do
  @moduledoc false

  alias DBF.Error
  alias DBF.Memo.DBT3
  alias DBF.Memo.DBT4
  alias DBF.Memo.FPT
  alias DBF.Resource

  @enforce_keys [:family, :block_size]
  defstruct [:family, :block_size]

  @type family :: :dbt_iii | :dbt_iv | :fpt
  @type t :: %__MODULE__{family: family(), block_size: pos_integer()}

  @spec initialize(Resource.t(), family(), non_neg_integer() | nil) ::
          {:ok, t()} | {:error, Error.t()}
  def initialize(resource, :dbt_iii, probe_block), do: DBT3.initialize(resource, probe_block)
  def initialize(resource, :dbt_iv, probe_block), do: DBT4.initialize(resource, probe_block)
  def initialize(resource, :fpt, probe_block), do: FPT.initialize(resource, probe_block)

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

  def get_block(resource, %__MODULE__{family: :fpt} = memo, block_number) do
    FPT.get_block(resource, memo, block_number)
  end
end
