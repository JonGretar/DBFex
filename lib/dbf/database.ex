defmodule DBF.Database do
  defstruct [
    :device,
    :memo_file,
    :version,
    :last_updated,
    :number_of_records,
    :header_bytes,
    :record_bytes,
    :fields,
    position: 0
  ]
  @type t :: %DBF.Database{
    device: File.stream,
    memo_file: DBF.Memo.t,
    version: integer,
    last_updated: {integer, integer, integer},
    number_of_records: integer,
    header_bytes: integer,
    record_bytes: integer,
    fields: [{binary, binary}],
    position: integer
  }

end

# Define the Enumerable implentation for the database.
defimpl Enumerable, for: DBF.Database do
  def count(_db) do
    # {:ok, db.number_of_records}
    {:error, __MODULE__}
  end

  def reduce(db, {:cont, acc}, fun) do
    if (db.position == db.number_of_records) do
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

  def slice(_array) do
    {:error, __MODULE__}
  end

  def member?(_array, _element) do
    {:error, __MODULE__}
  end

end
