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

  @versions %{
    0x02 => "FoxBase",
    0x03 => "dBase III without memo file",
    0x04 => "dBase IV without memo file",
    0x05 => "dBase V without memo file",
    0x07 => "Visual Objects 1.x",
    0x30 => "Visual FoxPro",
    0x31 => "Visual FoxPro with AutoIncrement field",
    0x32 => "Visual FoxPro with field type Varchar or Varbinary",
    0x43 => "dBASE IV SQL table files, no memo",
    0x63 => "dBASE IV SQL system files, no memo",
    0x7b => "dBase IV with memo file",
    0x83 => "dBase III with memo file",
    0x87 => "Visual Objects 1.x with memo file",
    0x8b => "dBase IV with memo file",
    0x8e => "dBase IV with SQL table",
    0xcb => "dBASE IV SQL table files, with memo",
    0xf5 => "FoxPro with memo file",
    0xe5 => "HiPer-Six format with SMT memo file",
    0xfb => "FoxPro without memo file"
  }


  def read_header(%__MODULE__{version: 0x02, device: device}=db) do
    {:ok, data} = :file.pread(device, 0, 8)

    <<
      _version::unsigned-integer-8,
      records::little-unsigned-integer-16,
      _unknown::binary-size(3),
      record_length::little-unsigned-integer-16,
    >> = data

    {:ok, %__MODULE__{ db |
      last_updated: Date.from_erl!({1900, 01, 01}),
      number_of_records: records,
      header_bytes: 521,
      record_bytes: record_length
    } }
  end

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


  @spec foxpro?(DBF.Database.t()) :: boolean()
  def foxpro?(%__MODULE__{version: version}) do
    version in [0x30, 0x31, 0x32, 0xf5, 0xfb]
  end

  @spec well_known_version?(DBF.Database.t()) :: boolean()
  def well_known_version?(%__MODULE__{version: version}) do
    Map.has_key?(@versions, version)
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
