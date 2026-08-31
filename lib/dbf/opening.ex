defmodule DBF.Opening do
  @moduledoc false

  alias DBF.Database
  alias DBF.Error
  alias DBF.FieldDescriptorLayout
  alias DBF.FormatProfile
  alias DBF.Header
  alias DBF.Memo
  alias DBF.Resource
  alias DBF.Schema

  @default_options memo_file: nil,
                   numeric: :float,
                   encoding: :auto,
                   encoding_errors: :raw

  @spec open(String.t(), term()) :: {:ok, Database.t()} | {:error, Error.t()}
  def open(filename, options) when is_binary(filename) do
    with {:ok, validated_options} <- validate_options(options) do
      Resource.transaction(filename, fn resource ->
        initialize_database(resource, filename, validated_options)
      end)
    end
  end

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
           Schema.parse(schema_binary, profile, header, options)
           |> add_error_context(filename: filename, version: version),
         {:ok, memo} <-
           initialize_memo(resource, filename, options, profile, header, schema) do
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
         text_decoder: schema.text_decoder,
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
    start = FieldDescriptorLayout.start(profile.field_descriptor_layout)
    length = header.header_length - start
    read_structure(resource, start, length, :invalid_schema)
  end

  defp read_structure(resource, offset, length, reason) do
    case Resource.read_exact(resource, :table, offset, length) do
      {:ok, binary} -> {:ok, binary}
      {:error, %Error{} = error} -> {:error, %Error{error | reason: reason}}
    end
  end

  defp initialize_memo(
         _resource,
         _filename,
         options,
         %FormatProfile{memo_family: :none},
         _header,
         _schema
       ) do
    case Keyword.fetch!(options, :memo_file) do
      nil ->
        {:ok, nil}

      memo_path ->
        {:error, Error.new(:invalid_options, :memo_not_supported, %{memo_file: memo_path})}
    end
  end

  defp initialize_memo(resource, filename, options, %FormatProfile{} = profile, header, schema) do
    with {:ok, probe_block} <- find_memo_probe(resource, header, schema) do
      paths = memo_paths(filename, Keyword.fetch!(options, :memo_file), profile.memo_family)
      acquire_and_initialize_memo(resource, paths, profile, probe_block, nil)
    end
  end

  defp acquire_and_initialize_memo(_resource, [], profile, _probe_block, last_error) do
    error =
      last_error ||
        Error.new(:missing_memo_file, :enoent, %{source: :memo, version: profile.version})

    {:error, Error.add_context(error, %{version: profile.version})}
  end

  defp acquire_and_initialize_memo(resource, [path | paths], profile, probe_block, _last_error) do
    case Resource.acquire_memo(resource, path) do
      {:ok, ^resource} ->
        Memo.initialize(resource, profile.memo_family, probe_block)
        |> add_error_context(filename: path, version: profile.version)

      {:error, %Error{reason: :missing_memo_file} = error} ->
        acquire_and_initialize_memo(resource, paths, profile, probe_block, error)

      {:error, %Error{} = error} ->
        {:error, Error.add_context(error, %{version: profile.version})}
    end
  end

  defp find_memo_probe(resource, header, schema) do
    memo_fields = Enum.filter(schema.fields, &(&1.type == "M"))
    find_memo_probe(resource, header, memo_fields, 0)
  end

  defp find_memo_probe(_resource, %{record_count: record_count}, _fields, record_count) do
    {:ok, nil}
  end

  defp find_memo_probe(resource, header, fields, record_number) do
    case find_record_memo_probe(resource, header, fields, record_number) do
      {:ok, nil} -> find_memo_probe(resource, header, fields, record_number + 1)
      result -> result
    end
  end

  defp find_record_memo_probe(_resource, _header, [], _record_number), do: {:ok, nil}

  defp find_record_memo_probe(resource, header, [field | fields], record_number) do
    offset = header.header_length + record_number * header.record_length + field.record_offset

    case Resource.read_exact(resource, :table, offset, field.length) do
      {:ok, raw_pointer} ->
        case parse_memo_probe(raw_pointer, record_number, field, offset) do
          {:ok, nil} -> find_record_memo_probe(resource, header, fields, record_number)
          result -> result
        end

      {:error, %Error{} = error} ->
        {:error, %Error{error | reason: :invalid_memo}}
    end
  end

  defp parse_memo_probe(raw_pointer, record_number, field, offset) do
    pointer = String.trim(raw_pointer)

    case Integer.parse(pointer) do
      {block, ""} when block >= 1 ->
        {:ok, block}

      :error when pointer == "" ->
        {:ok, nil}

      _invalid ->
        {:error,
         Error.new(:invalid_memo, :invalid_memo_pointer, %{
           raw_pointer: pointer,
           record_number: record_number,
           field_name: field.name,
           field_type: field.type,
           offset: offset
         })}
    end
  end

  defp memo_paths(_filename, memo_path, _family) when is_binary(memo_path), do: [memo_path]

  defp memo_paths(filename, nil, family) do
    root = Path.rootname(filename)

    case family do
      family when family in [:dbt_iii, :dbt_iv] -> [root <> ".dbt", root <> ".DBT"]
      :fpt -> [root <> ".fpt", root <> ".FPT"]
    end
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
    with :ok <- validate_memo_file(Keyword.fetch!(options, :memo_file)),
         :ok <- validate_numeric_policy(Keyword.fetch!(options, :numeric)),
         :ok <- validate_encoding(Keyword.fetch!(options, :encoding)),
         :ok <- validate_encoding_errors(Keyword.fetch!(options, :encoding_errors)) do
      {:ok, options}
    end
  end

  defp validate_memo_file(value) when is_binary(value) or is_nil(value), do: :ok

  defp validate_memo_file(value) do
    {:error, Error.new(:invalid_options, {:invalid_memo_file, value}, %{})}
  end

  defp validate_numeric_policy(value) when value in [:float, :exact], do: :ok

  defp validate_numeric_policy(value) do
    {:error, Error.new(:invalid_options, {:invalid_numeric_policy, value}, %{})}
  end

  defp validate_encoding(value)
       when value in [:auto, :raw, :windows_1251, :windows_1252],
       do: :ok

  defp validate_encoding(value) do
    {:error, Error.new(:invalid_options, {:invalid_encoding, value}, %{})}
  end

  defp validate_encoding_errors(value) when value in [:strict, :replace, :raw], do: :ok

  defp validate_encoding_errors(value) do
    {:error, Error.new(:invalid_options, {:invalid_encoding_errors, value}, %{})}
  end

  defp add_error_context({:ok, _value} = result, _context), do: result

  defp add_error_context({:error, %Error{} = error}, context) do
    {:error, Error.add_context(error, context)}
  end
end
