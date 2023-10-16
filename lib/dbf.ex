defmodule DBF do
  alias DBF.Database, as: DB
  alias DBF.Fields, as: F
  alias DBF.Record, as: R
  alias DBF.Memo, as: M

  @moduledoc """
  Documentation for `DBF`.
  """


  def open(filename) when is_binary(filename) do
    {:ok, file} = File.open(filename, [:read, :binary])
    {:ok, data} = :file.pread(file, 0, 32)

    <<
      version::unsigned-integer-8,
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

    {:ok, raw_fields} = :file.pread(file, 32, header_length-32)

    {:ok, %DB{
      device: file,
      memo_file: M.sense_memo_file(filename),
      version: version,
      last_updated: Date.from_erl!({year + 1900, month, day}),
      number_of_records: records,
      header_bytes: header_length,
      record_bytes: record_length,
      fields: F.parse_fields(raw_fields)
    }}
  end

  def open!(filename) when is_binary(filename) do
    {:ok, db} = open(filename)
    db
  end

  def close!(%DBF.Database{device: dev}) do
    File.close(dev)
  end

  def read_records(db) do
    data1 = get(db, 0)
    data2 = get(db, 1)
    IO.puts("Ze Data")
    IO.puts("data1: #{inspect(data1)}")
    IO.puts("data2: #{inspect(data2)}")
  end

  def get(%DBF.Database{device: dev,
                        record_bytes: record_bytes,
                        header_bytes: header_bytes
                        } = db, record_number) do
    offset = header_bytes + record_number * record_bytes
    {:ok, <<raw_type::binary-size(1), data::binary>>} = :file.pread(dev, offset, record_bytes)
    type = case raw_type do
      " " -> :record
      "*" -> :deleted_record
      _ -> :unknown
    end
    {type, R.parse_record(db, data)}
  end




end
