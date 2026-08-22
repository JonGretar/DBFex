defmodule DBF.Database do
  @moduledoc """
  An open DBF database.

  Values are returned by `DBF.open/1,2` and implement `Enumerable` over the
  database records. Treat this structure as opaque and use the `DBF` API.
  """

  defstruct [
    :resource,
    :filename,
    :memo_file,
    :profile,
    :schema,
    version: 0,
    options: [],
    last_updated: ~D[1900-01-01],
    number_of_records: 0,
    header_bytes: 0,
    record_bytes: 0,
    table_flags: nil,
    language_driver: nil,
    fields: [],
    position: 0
  ]

  @type t :: %__MODULE__{
          resource: term(),
          filename: String.t(),
          memo_file: term(),
          profile: term(),
          schema: DBF.Schema.t(),
          version: byte(),
          options: DBF.options(),
          last_updated: Date.t(),
          number_of_records: non_neg_integer(),
          header_bytes: pos_integer(),
          record_bytes: pos_integer(),
          table_flags: byte() | nil,
          language_driver: byte() | nil,
          fields: [DBF.Field.t()],
          position: non_neg_integer()
        }
end

# Define the Enumerable implementation for the database.
defimpl Enumerable, for: DBF.Database do
  @spec count(DBF.Database.t()) :: {:ok, non_neg_integer()}
  def count(db) do
    {:ok, db.number_of_records}
  end

  @spec reduce(DBF.Database.t(), Enumerable.acc(), Enumerable.reducer()) :: Enumerable.result()
  def reduce(db, {:cont, acc}, fun) do
    if db.position == db.number_of_records do
      {:done, acc}
    else
      record = DBF.get(db, db.position)
      reduce(Map.put(db, :position, db.position + 1), fun.(record, acc), fun)
    end
  end

  def reduce(_db, {:halt, acc}, _fun) do
    {:halted, acc}
  end

  def reduce(db, {:suspend, acc}, fun) do
    {:suspended, acc, &reduce(db, &1, fun)}
  end

  @spec slice(DBF.Database.t()) :: {:error, module()}
  def slice(_database) do
    {:error, __MODULE__}
  end

  @spec member?(DBF.Database.t(), term()) :: {:error, module()}
  def member?(_database, _element) do
    {:error, __MODULE__}
  end
end
