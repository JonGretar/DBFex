defmodule DBF do
  alias DBF.Database
  alias DBF.Field
  alias DBF.Record
  alias DBF.Memo
  # alias DBF.DatabaseError

  @type options() :: [
    memo_file: String.t() | nil,
    allow_missing_memo: boolean()
  ]

  @default_options [
    memo_file: nil,
    allow_missing_memo: false
  ]

  @moduledoc """
  Documentation for `DBF`.
  """

  @spec open(String.t()) :: {:ok, Database.t()} | {:error, Error.t()}
  @spec open(String.t(), options()) :: {:ok, Database.t()} | {:error, atom()}
  def open(filename, options \\ []) when is_binary(filename) do
    with {:ok, db} <- create_database_struct(filename, options),
         {:ok, db} <- read_version(db),
         {:ok, db} <- Database.read_header(db),
         {:ok, db} <- open_memo_file(db),
         {:ok, db} <- Field.parse_fields(db)
    do
      {:ok, db}
    else
      error -> error
    end
  end

  @spec open!(String.t(), options()) :: Database.t()
  @spec open!(binary()) :: Database.t()
  def open!(filename, options \\ []) when is_binary(filename) do
    case open(filename, options) do
      {:ok, db} -> db
      {:error, error} -> raise error
    end
  end

  @spec close(Database.t()) :: :ok | {:error, atom()}
  def close(%Database{device: dev}=db) when is_struct(db, Database) do
    if db.memo_file do
      File.close(db.memo_file.device)
    end
    File.close(dev)
  end

  @spec get(Database.t(), integer()) ::
          {:deleted_record, map()} | {:record, map()} | {:unknown, map()}
  def get(%Database{number_of_records: total}, record_number) when record_number >= total do
    {:error, :record_not_found}
  end
  def get(%Database{device: dev,
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
    {type, Record.parse_record(db, data)}
  end

  @spec has_memo_file?(Database.t()) :: boolean()
  def has_memo_file?(%Database{memo_file: nil}), do: false
  def has_memo_file?(%Database{memo_file: _}), do: true

  defp open_memo_file(%Database{version: version}=db) do
    case search_memo_file(db) do
      nil ->
        {:ok, db}
      memo_filename ->
        {:ok, memo_file} = Memo.open(memo_filename, version)
        {:ok, %Database{db | memo_file: memo_file} }
    end
  end

  @spec search_memo_file(Database.t()) :: String.t() | nil
  defp search_memo_file(db) when is_struct(db) do

    d = options(db, :memo_file)
    case d do
      nil ->
        search_memo_file_wildly(db.filename)
      memo_filename when is_binary(memo_filename) ->
        memo_filename
    end
  end

  defp search_memo_file_wildly(filename) do
    search_path = (filename |> Path.rootname() ) <> ".{fpt,FPT,dbt,DBT}"
    case Path.wildcard(search_path) do
      [memo_filename] -> memo_filename
      [] -> nil
      _ -> raise "Multiple memo files found for #{filename}"
    end
  end


  def options(%Database{options: options}, key) do
    if Keyword.has_key?(options, key) do
      Keyword.get(options, key)
    else
      Keyword.get(@default_options, key)
    end
  end

  defp read_version(db) do
    {:ok, <<version::unsigned-integer-8>>} = :file.pread(db.device, 0, 1)
    {:ok, %Database{db | version: version}}
  end

  defp create_database_struct(filename, options) do
    with {:ok, file} <- File.open(filename, [:read, :binary]),
         :ok <- validate_options(options)
    do
      {:ok, %Database{filename: filename, device: file, options: options} }
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_options([{key, _}|rest]) do
    if Keyword.has_key?(@default_options, key) do
      validate_options(rest)
    else
      {:error, :invalid_option}
    end
  end
  defp validate_options([]) do
    :ok
  end

end
