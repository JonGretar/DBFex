defmodule DBF do
  alias DBF.Database
  alias DBF.DatabaseError
  alias DBF.Field
  alias DBF.Memo
  alias DBF.Record

  @type option() :: {:memo_file, String.t() | nil}
  @type options() :: [option()]
  @type record() :: %{optional(String.t()) => term()}
  @type record_status() :: :record | :deleted_record
  @type error_reason() ::
          :file_not_found
          | :file_error
          | :close_failed
          | :invalid_options
          | :invalid_record_index
          | :unsupported_version
          | :missing_memo_file
          | :unsupported_field_type
          | :invalid_header
          | :invalid_schema
          | :invalid_record
          | :invalid_memo
  @type error_result() :: {:error, DatabaseError.t()}
  @type record_result() :: {record_status(), record()} | error_result()
  @type open_result() :: {:ok, Database.t()} | error_result()
  @type close_result() :: :ok | error_result()
  @type with_open_result(result) :: result | error_result()

  @default_options [
    memo_file: nil
    # allow_missing_memo: false
  ]

  @moduledoc """
  Read DBASE files in Elixir.

  DBFex currently provides read-only access. For callback-scoped reads, prefer
  `with_open/2` so resources are closed automatically:

  ```elixir
  DBF.with_open("test/dbf_files/bayarea_zipcodes.dbf", fn db ->
    Enum.to_list(db)
  end)
  ```

  An open database implements `Enumerable`. Each record is returned as
  `{:record, values}`, `{:deleted_record, values}`, or an error tuple. Use
  `get/2` for a specific zero-based record index.

  Use `open/1,2` and `close/1` directly for streaming, suspended enumeration, or
  longer-lived access.
  """

  @doc """
  Open a DBase database file.
  """
  @spec open(String.t()) :: open_result()
  @spec open(String.t(), options()) :: open_result()
  def open(filename, options \\ []) when is_binary(filename) do
    with {:ok, db} <- create_database_struct(filename, options),
         {:ok, db} <- Database.open_database(db),
         {:ok, db} <- open_memo_file(db) do
      Field.parse_fields(db)
    end
  end

  @doc """
  Opens a database for the duration of a callback and always attempts to close it.

  The callback result is returned unchanged. If opening or closing fails, an error
  tuple is returned. If the callback raises, throws, or exits, the database is
  closed before the original failure is propagated.

  The callback must not close the database itself.
  """
  @spec with_open(String.t(), (Database.t() -> result)) :: with_open_result(result)
        when result: term()
  @spec with_open(String.t(), options(), (Database.t() -> result)) :: with_open_result(result)
        when result: term()
  def with_open(filename, fun) when is_binary(filename) and is_function(fun, 1) do
    with_open(filename, [], fun)
  end

  def with_open(filename, options, fun)
      when is_binary(filename) and is_function(fun, 1) do
    case open(filename, options) do
      {:ok, db} -> invoke_and_close(db, fun)
      {:error, _error} = error -> error
    end
  end

  @doc """
  Same as `open/2`, but raises `DBF.DatabaseError` on failure.
  """
  @spec open!(String.t()) :: Database.t()
  @spec open!(String.t(), options()) :: Database.t()
  def open!(filename, options \\ []) when is_binary(filename) do
    case open(filename, options) do
      {:ok, db} -> db
      {:error, error} -> raise error
    end
  end

  @doc """
  Closes the file access.
  """
  @spec close(Database.t()) :: close_result()
  def close(%Database{device: dev} = db) when is_struct(db, Database) do
    if db.memo_file do
      File.close(db.memo_file.device)
    end

    File.close(dev)
  end

  @doc """
  Get a record by number.
  """
  @spec get(Database.t(), non_neg_integer()) :: record_result()
  def get(%Database{number_of_records: total}, record_number) when record_number >= total do
    {:error, :record_not_found}
  end

  def get(
        %Database{device: dev, record_bytes: record_bytes, header_bytes: header_bytes} = db,
        record_number
      ) do
    offset = header_bytes + record_number * record_bytes
    {:ok, <<raw_type::binary-size(1), data::binary>>} = :file.pread(dev, offset, record_bytes)

    type =
      case raw_type do
        " " -> :record
        "*" -> :deleted_record
        _ -> :unknown
      end

    {type, Record.parse_record(db, data)}
  end

  @spec has_memo_file?(Database.t()) :: boolean()
  def has_memo_file?(%Database{memo_file: nil}), do: false
  def has_memo_file?(%Database{memo_file: _}), do: true

  defp open_memo_file(%Database{version: version} = db) do
    case search_memo_file(db) do
      nil ->
        {:ok, db}

      memo_filename ->
        {:ok, memo_file} = Memo.open(memo_filename, version)
        {:ok, %Database{db | memo_file: memo_file}}
    end
  end

  @spec search_memo_file(Database.t()) :: String.t() | nil
  defp search_memo_file(db) when is_struct(db) do
    case options(db, :memo_file) do
      nil ->
        search_memo_file_wildly(db.filename)

      memo_filename when is_binary(memo_filename) ->
        memo_filename
    end
  end

  defp search_memo_file_wildly(filename) do
    search_path = (filename |> Path.rootname()) <> ".{fpt,FPT,dbt,DBT}"

    case Path.wildcard(search_path) do
      [] -> nil
      memo_file_list when is_list(memo_file_list) -> hd(memo_file_list)
    end
  end

  @doc false
  @spec options(DBF.Database.t(), atom()) :: any()
  def options(%Database{options: options}, key) do
    if Keyword.has_key?(options, key) do
      Keyword.get(options, key)
    else
      Keyword.get(@default_options, key)
    end
  end

  defp invoke_and_close(db, fun) do
    result = fun.(db)

    db
    |> close()
    |> finish_with_close(result)
  catch
    kind, reason ->
      stacktrace = __STACKTRACE__
      _ = close(db)
      :erlang.raise(kind, reason, stacktrace)
  end

  # Current valid file handles infer `:ok`; keep the error branch for the public
  # close contract and the Phase 1 resource implementation.
  @dialyzer {:nowarn_function, finish_with_close: 2}
  @spec finish_with_close(close_result(), result) :: with_open_result(result) when result: term()
  defp finish_with_close(:ok, result), do: result
  defp finish_with_close({:error, _reason} = error, _result), do: error

  defp create_database_struct(filename, options) do
    with {:ok, file} <- File.open(filename, [:read, :binary]),
         {:ok, validated_options} <- validate_options(options) do
      {:ok, %Database{filename: filename, device: file, options: validated_options}}
    end
  end

  defp validate_options(option) do
    # TODO: This needs to be fixed to be modern
    case Keyword.validate(option, @default_options) do
      {:ok, result} -> {:ok, result}
      {:error, _} -> {:error, DatabaseError.new(:invalid_option)}
    end
  end
end
