defmodule DBF do
  alias DBF.Database, as: DB
  alias DBF.Field, as: F
  alias DBF.Record, as: R
  alias DBF.Memo, as: M

  @moduledoc """
  Documentation for `DBF`.
  """


  @spec open(binary()) :: {:ok, DBF.Database.t()}
  def open(filename) when is_binary(filename) do
    {:ok, file} = File.open(filename, [:read, :binary])

    {:ok, <<version::unsigned-integer-8>>} = :file.pread(file, 0, 1)

    {:ok, db} = DB.read_header(%DB{
      device: file,
      filename: filename,
      version: version
    })

    {:ok, %DB{ db |
      memo_file: M.find_memo_file(db.filename),
      fields: F.parse_fields(db)
    }}
  end

  @spec open!(binary()) :: DBF.Database.t()
  def open!(filename) when is_binary(filename) do
    {:ok, db} = open(filename)
    db
  end

  @spec close(DBF.Database.t()) :: :ok | {:error, atom()}
  def close(%DBF.Database{device: dev}=db) when is_struct(db, DBF.Database) do
    if db.memo_file do
      File.close(db.memo_file.device)
    end
    File.close(dev)
  end


  @spec get(DBF.Database.t(), integer()) ::
          {:deleted_record, list()} | {:record, list()} | {:unknown, list()}
  def get(%DBF.Database{number_of_records: total}, record_number) when record_number >= total do
    {:error, :record_not_found}
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
