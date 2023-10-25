defmodule DBF do
  alias DBF.Database, as: DB
  alias DBF.Field, as: F
  alias DBF.Record, as: R
  alias DBF.Memo, as: M

  @moduledoc """
  Documentation for `DBF`.
  """


  @spec open(binary()) :: {:ok, DBF.Database.t()} | {:error, any()}
  def open(filename) when is_binary(filename) do
    db = %DB{filename: filename}
    with {:ok, file} <- File.open(db.filename, [:read, :binary]),
         {:ok, db} = read_version(%DB{db | device: file}),
         {:ok, db} = DB.read_header(db),
         {:ok, db} = M.find_memo_file(db),
         {:ok, db} = F.parse_fields(db) do
      {:ok, db}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @spec open!(binary()) :: DBF.Database.t()
  def open!(filename) when is_binary(filename) do
    case open(filename) do
      {:ok, db} -> db
      {:error, reason} -> raise DBF.DatabaseError, reason: reason
    end
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

  defp read_version(db) do
    {:ok, <<version::unsigned-integer-8>>} = :file.pread(db.device, 0, 1)
    {:ok, %DB{db | version: version}}
  end

end
