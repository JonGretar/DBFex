defmodule DBF do
  alias DBF.Database
  alias DBF.DatabaseError
  alias DBF.Error
  alias DBF.FormatProfile
  alias DBF.Header
  alias DBF.Memo
  alias DBF.Record
  alias DBF.Resource
  alias DBF.Schema

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

  @default_options memo_file: nil

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
  Opens a DBF database file.
  """
  @spec open(String.t()) :: open_result()
  @spec open(String.t(), options()) :: open_result()
  def open(filename, options \\ []) when is_binary(filename) do
    case validate_options(options) do
      {:ok, validated_options} ->
        filename
        |> Resource.transaction(fn resource ->
          initialize_database(resource, filename, validated_options)
        end)
        |> public_result()

      {:error, %Error{} = error} ->
        public_error(error)
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
      {:error, %DatabaseError{}} = error -> error
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
      {:error, %DatabaseError{} = error} -> raise error
    end
  end

  @doc """
  Closes all resources owned by an open database.

  Closing the same database more than once is safe.
  """
  @spec close(Database.t()) :: close_result()
  def close(%Database{resource: resource}) do
    case Resource.close(resource) do
      :ok -> :ok
      {:error, %Error{} = error} -> public_error(error)
    end
  end

  @doc """
  Gets a record by its zero-based physical index.
  """
  @spec get(Database.t(), term()) :: record_result()
  def get(%Database{number_of_records: total}, record_number)
      when not is_integer(record_number) or record_number < 0 or record_number >= total do
    Error.new(:invalid_record_index, :out_of_bounds, %{
      record_number: record_number,
      record_count: total
    })
    |> public_error()
  end

  def get(
        %Database{resource: resource, record_bytes: record_bytes, header_bytes: header_bytes} =
          db,
        record_number
      ) do
    offset = header_bytes + record_number * record_bytes

    case Resource.read_exact(resource, :table, offset, record_bytes) do
      {:ok, <<" ", data::binary>>} ->
        decode_record(db, :record, data, record_number, offset)

      {:ok, <<"*", data::binary>>} ->
        decode_record(db, :deleted_record, data, record_number, offset)

      {:ok, <<marker, _data::binary>>} ->
        Error.new(:invalid_record, {:unknown_record_marker, marker}, %{
          record_number: record_number,
          offset: offset,
          version: db.version
        })
        |> public_error()

      {:error, %Error{} = error} ->
        error
        |> record_read_error()
        |> Error.add_context(%{record_number: record_number, offset: offset, version: db.version})
        |> public_error()
    end
  end

  @doc false
  @spec has_memo_file?(Database.t()) :: boolean()
  def has_memo_file?(%Database{memo_file: nil}), do: false
  def has_memo_file?(%Database{memo_file: _memo}), do: true

  @doc false
  @spec options(Database.t(), atom()) :: term()
  def options(%Database{options: options}, key), do: Keyword.get(options, key)

  defp decode_record(db, status, data, record_number, offset) do
    case Record.parse_record(db, data) do
      {:ok, record} ->
        {status, record}

      {:error, %Error{} = error} ->
        error
        |> Error.add_context(%{
          record_number: record_number,
          offset: offset,
          version: db.version
        })
        |> public_error()
    end
  end

  defp record_read_error(%Error{cause: :eof} = error), do: %Error{error | reason: :invalid_record}
  defp record_read_error(%Error{} = error), do: error

  defp initialize_database(resource, filename, options) do
    with {:ok, file_size} <- Resource.size(resource, :table),
         {:ok, version} <- read_version(resource),
         {:ok, profile} <- FormatProfile.select(version) |> add_error_context(filename: filename),
         {:ok, header_binary} <-
           read_structure(resource, 0, Header.required_bytes(profile), :invalid_header),
         {:ok, header} <-
           Header.parse(header_binary, profile, file_size)
           |> add_error_context(filename: filename, version: version),
         {:ok, schema_binary} <- read_schema(resource, profile, header),
         {:ok, schema} <-
           Schema.parse(schema_binary, profile, header)
           |> add_error_context(filename: filename, version: version),
         {:ok, memo} <- initialize_memo(resource, filename, options, profile) do
      {:ok,
       %Database{
         resource: resource,
         filename: filename,
         memo_file: memo,
         profile: profile,
         version: version,
         options: options,
         last_updated: header.date,
         number_of_records: header.record_count,
         header_bytes: header.header_length,
         record_bytes: header.record_length,
         table_flags: header.table_flags,
         language_driver: header.language_driver,
         schema: schema,
         fields: schema.fields
       }}
    end
  end

  defp read_version(resource) do
    case read_structure(resource, 0, 1, :invalid_header) do
      {:ok, <<version>>} -> {:ok, version}
      {:error, %Error{} = error} -> {:error, error}
    end
  end

  defp read_schema(resource, profile, header) do
    start = descriptor_start(profile.field_descriptor_layout)
    length = header.header_length - start
    read_structure(resource, start, length, :invalid_schema)
  end

  defp read_structure(resource, offset, length, reason) do
    case Resource.read_exact(resource, :table, offset, length) do
      {:ok, binary} -> {:ok, binary}
      {:error, %Error{} = error} -> {:error, %Error{error | reason: reason}}
    end
  end

  defp initialize_memo(_resource, _filename, options, %FormatProfile{memo_family: :none}) do
    case Keyword.fetch!(options, :memo_file) do
      nil ->
        {:ok, nil}

      memo_path ->
        {:error, Error.new(:invalid_options, :memo_not_supported, %{memo_file: memo_path})}
    end
  end

  defp initialize_memo(resource, filename, options, %FormatProfile{} = profile) do
    paths = memo_paths(filename, Keyword.fetch!(options, :memo_file))
    acquire_and_initialize_memo(resource, paths, profile, nil)
  end

  defp acquire_and_initialize_memo(_resource, [], profile, last_error) do
    error =
      last_error ||
        Error.new(:missing_memo_file, :enoent, %{source: :memo, version: profile.version})

    {:error, Error.add_context(error, %{version: profile.version})}
  end

  defp acquire_and_initialize_memo(resource, [path | paths], profile, _last_error) do
    case Resource.acquire_memo(resource, path) do
      {:ok, ^resource} ->
        Memo.initialize(resource, profile.memo_family)
        |> add_error_context(filename: path, version: profile.version)

      {:error, %Error{reason: :missing_memo_file} = error} ->
        acquire_and_initialize_memo(resource, paths, profile, error)

      {:error, %Error{} = error} ->
        {:error, Error.add_context(error, %{version: profile.version})}
    end
  end

  defp memo_paths(_filename, memo_path) when is_binary(memo_path), do: [memo_path]

  defp memo_paths(filename, nil) do
    root = Path.rootname(filename)
    [root <> ".dbt", root <> ".DBT"]
  end

  defp validate_options(options) when is_list(options) do
    if Keyword.keyword?(options) do
      case Keyword.validate(options, @default_options) do
        {:ok, validated} -> validate_option_values(validated)
        {:error, keys} -> {:error, Error.new(:invalid_options, {:unknown_options, keys}, %{})}
      end
    else
      {:error, Error.new(:invalid_options, :not_a_keyword_list, %{})}
    end
  end

  defp validate_options(_options) do
    {:error, Error.new(:invalid_options, :not_a_keyword_list, %{})}
  end

  defp validate_option_values(options) do
    case Keyword.fetch!(options, :memo_file) do
      value when is_binary(value) or is_nil(value) -> {:ok, options}
      value -> {:error, Error.new(:invalid_options, {:invalid_memo_file, value}, %{})}
    end
  end

  defp invoke_and_close(db, fun) do
    result = fun.(db)

    case close(db) do
      :ok -> result
      {:error, %DatabaseError{}} = error -> error
    end
  catch
    kind, reason ->
      stacktrace = __STACKTRACE__
      _ = close(db)
      :erlang.raise(kind, reason, stacktrace)
  end

  defp public_result({:ok, value}), do: {:ok, value}
  defp public_result({:error, %Error{} = error}), do: public_error(error)

  defp public_error(%Error{} = error) do
    {:error, DatabaseError.from_internal(error)}
  end

  defp add_error_context({:ok, _value} = result, _context), do: result

  defp add_error_context({:error, %Error{} = error}, context) do
    {:error, Error.add_context(error, context)}
  end

  defp descriptor_start(:foxbase_16), do: 8
  defp descriptor_start(:dbase_legacy_32), do: 32
end
