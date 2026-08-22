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
    fields: []
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
          fields: [DBF.Field.t()]
        }
end

# Define the Enumerable implementation for the database.
defimpl Enumerable, for: DBF.Database do
  @spec count(DBF.Database.t()) :: {:ok, non_neg_integer()}
  def count(db) do
    {:ok, db.number_of_records}
  end

  @spec reduce(DBF.Database.t(), Enumerable.acc(), Enumerable.reducer()) :: Enumerable.result()
  def reduce(db, acc, fun), do: reduce(db, 0, acc, fun)

  defp reduce(_db, _position, {:halt, acc}, _fun), do: {:halted, acc}

  defp reduce(db, position, {:suspend, acc}, fun) do
    {:suspended, acc, &reduce(db, position, &1, fun)}
  end

  defp reduce(%{number_of_records: position}, position, {:cont, acc}, _fun) do
    {:done, acc}
  end

  defp reduce(db, position, {:cont, acc}, fun) do
    record = DBF.get(db, position)
    next = fun.(record, acc)

    case record do
      {:error, %DBF.DatabaseError{}} -> finish(next)
      _record -> reduce(db, position + 1, next, fun)
    end
  end

  defp finish({:cont, acc}), do: {:done, acc}
  defp finish({:halt, acc}), do: {:halted, acc}
  defp finish({:suspend, acc}), do: {:suspended, acc, &finish/1}

  @spec slice(DBF.Database.t()) :: {:error, module()}
  def slice(_database) do
    {:error, __MODULE__}
  end

  @spec member?(DBF.Database.t(), term()) :: {:error, module()}
  def member?(_database, _element) do
    {:error, __MODULE__}
  end
end
