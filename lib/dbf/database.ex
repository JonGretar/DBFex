defmodule DBF.Database do
  defstruct [
    :device,
    :filename,
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
    filename: String.t,
    memo_file: DBF.Memo.t,
    version: integer,
    last_updated: {integer, integer, integer},
    number_of_records: integer,
    header_bytes: integer,
    record_bytes: integer,
    fields: [{binary, binary}],
    position: integer
  }


  def read_header(%__MODULE__{device: device}=db) do
    {:ok, data} = :file.pread(device, 0, 32)

    <<
      _version::unsigned-integer-8,
      year::unsigned-integer-8,
      month::unsigned-integer-8,
      day::unsigned-integer-8,
      records::little-unsigned-integer-32,
      header_length::little-unsigned-integer-16,
      record_length::little-unsigned-integer-16,
      _reserved1::binary-size(2),
      _transaction::binary-size(1),
      _reserved2::binary-size(12),
      _table_flags::binary-size(1),
      _code_page_mark::binary-size(1),
      _reserved3::binary-size(2),
      _header_terminator::binary-size(1)
    >> = data

    {:ok, %__MODULE__{ db |
      last_updated: Date.from_erl!({year + 1900, month, day}),
      number_of_records: records,
      header_bytes: header_length,
      record_bytes: record_length
    } }
  end

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
