defmodule DBF do
  alias DBF.Database
  alias DBF.DatabaseError
  alias DBF.Error
  alias DBF.Opening
  alias DBF.Record
  alias DBF.Resource

  @type numeric_policy() :: :float | :exact
  @type encoding() :: :auto | :raw | :windows_1251 | :windows_1252
  @type encoding_error_policy() :: :strict | :replace | :raw
  @type option() ::
          {:memo_file, String.t() | nil}
          | {:numeric, numeric_policy()}
          | {:encoding, encoding()}
          | {:encoding_errors, encoding_error_policy()}
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
          | :invalid_encoding
  @type error_result() :: {:error, DatabaseError.t()}
  @type record_result() :: {record_status(), record()} | error_result()
  @type open_result() :: {:ok, Database.t()} | error_result()
  @type close_result() :: :ok | error_result()
  @type with_open_result(result) :: result | error_result()

  @moduledoc """
  Read FoxBase and dBASE DBF files.

  DBFex provides read-only, positional access to records. For ordinary reads,
  prefer `with_open/2` or `with_open/3`; it owns the database resource for the
  duration of the callback and closes it automatically:

  ```elixir
  DBF.with_open("customers.dbf", fn db ->
    Enum.to_list(db)
  end)
  ```

  ## Records and enumeration

  An open `DBF.Database` implements `Enumerable`. Elements retain the physical
  record status and have one of these forms:

  ```elixir
  {:record, %{"NAME" => "Ada"}}
  {:deleted_record, %{"NAME" => "Grace"}}
  {:error, %DBF.DatabaseError{}}
  ```

  Enumeration includes active and deleted records in file order. If decoding a
  record fails, the error tuple is emitted as the final element. Use `get/2` for
  zero-based random access to a single physical record.

  ## Options

  The same options are accepted by `open/2`, `open!/2`, and `with_open/3`:

  * `:memo_file` - an explicit DBT path, or `nil` for automatic companion
    discovery. Defaults to `nil`.
  * `:numeric` - `:float` for compatible float results, or `:exact` for integers
    and `Decimal` values. Defaults to `:float`.
  * `:encoding` - `:auto`, `:raw`, `:windows_1251`, or `:windows_1252`. Defaults
    to `:auto`.
  * `:encoding_errors` - `:strict`, `:replace`, or `:raw`. Defaults to `:raw`.

  For example, to read exact numeric values and require valid Windows-1252 text:

  ```elixir
  DBF.with_open(
    "customers.dbf",
    [numeric: :exact, encoding: :windows_1252, encoding_errors: :strict],
    fn db -> DBF.get(db, 0) end
  )
  ```

  ## Resource ownership and errors

  Use `open/1,2` with `close/1` when the database must outlive a callback, such
  as for suspended enumeration. Every successful open must have a corresponding
  close. `close/1` is idempotent.

  Non-bang operations return `{:error, %DBF.DatabaseError{}}`. `open!/1,2`
  raises that same exception type when opening fails.
  """

  @doc """
  Opens a DBF file and returns an opaque database value.

  The caller owns the returned resource and must eventually call `close/1`.
  Prefer `with_open/2,3` when callback-scoped access is sufficient.

  Options are described in the module documentation.

  ## Example

  ```elixir
  case DBF.open("customers.dbf", numeric: :exact) do
    {:ok, db} ->
      try do
        DBF.get(db, 0)
      after
        DBF.close(db)
      end

    {:error, error} ->
      {:error, Exception.message(error)}
  end
  ```
  """
  @spec open(String.t()) :: open_result()
  @spec open(String.t(), options()) :: open_result()
  def open(filename, options \\ []) when is_binary(filename) do
    filename
    |> Opening.open(options)
    |> public_result()
  end

  @doc """
  Opens a database for the duration of a callback and always attempts to close it.

  This is the preferred lifecycle for complete reads. The callback result is
  returned unchanged. If opening or closing fails, an error tuple is returned.
  If the callback raises, throws, or exits, DBFex closes the resources before
  propagating the original failure.

  The callback receives an enumerable `DBF.Database` and must not close it.

  ## Examples

  Read every physical record:

  ```elixir
  DBF.with_open("customers.dbf", fn db ->
    Enum.to_list(db)
  end)
  ```

  Pass decoding options and keep only active rows:

  ```elixir
  DBF.with_open("customers.dbf", [numeric: :exact], fn db ->
    Enum.flat_map(db, fn
      {:record, row} -> [row]
      {:deleted_record, _row} -> []
      {:error, error} -> raise error
    end)
  end)
  ```
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
  Opens a DBF file, raising `DBF.DatabaseError` on failure.

  Like `open/2`, the caller owns the returned resource and must call `close/1`.
  This is useful when failure should abort the current operation:

  ```elixir
  db = DBF.open!("customers.dbf")

  try do
    Enum.take(db, 10)
  after
    DBF.close(db)
  end
  ```
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
  Closes the DBF and memo resources owned by an open database.

  Closing the same database more than once is safe. After closing, the database
  must not be used for random access or resumed enumeration.

  ```elixir
  {:ok, db} = DBF.open("customers.dbf")
  :ok = DBF.close(db)
  :ok = DBF.close(db)
  ```
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

  Active and deleted records retain their status. Invalid indexes return an
  `:invalid_record_index` database error.

  ```elixir
  DBF.with_open("customers.dbf", fn db ->
    case DBF.get(db, 2) do
      {:record, row} -> {:ok, row}
      {:deleted_record, row} -> {:deleted, row}
      {:error, error} -> {:error, error}
    end
  end)
  ```
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
end
