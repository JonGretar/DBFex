defmodule DBF.TestFixture do
  @moduledoc false

  def write_temp!(binary, basename \\ "synthetic.dbf") when is_binary(binary) do
    directory =
      Path.join(
        System.tmp_dir!(),
        "dbf_ex_#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(directory)
    path = Path.join(directory, basename)
    File.write!(path, binary)
    path
  end

  def with_record_marker!(source_path, record_index, marker)
      when is_integer(record_index) and record_index >= 0 and byte_size(marker) == 1 do
    binary = File.read!(source_path)

    <<_::binary-size(8), header_bytes::little-unsigned-integer-16,
      record_bytes::little-unsigned-integer-16, _::binary>> = binary

    offset = header_bytes + record_index * record_bytes
    <<prefix::binary-size(offset), _old_marker::binary-size(1), rest::binary>> = binary

    write_temp!(prefix <> marker <> rest, Path.basename(source_path))
  end

  def legacy_dbf(options \\ []) do
    version = Keyword.get(options, :version, 0x03)
    year = Keyword.get(options, :year, 124)
    month = Keyword.get(options, :month, 1)
    day = Keyword.get(options, :day, 1)
    record_count = Keyword.get(options, :record_count, 0)
    field_length = Keyword.get(options, :field_length, 1)
    field_type = Keyword.get(options, :field_type, "C")
    field_name = Keyword.get(options, :field_name, "VALUE")
    decimal = Keyword.get(options, :decimal, 0)
    descriptor = legacy_descriptor(field_name, field_type, field_length, decimal)
    terminator = if Keyword.get(options, :terminator, true), do: <<0x0D>>, else: <<>>
    schema = descriptor <> terminator
    header_length = Keyword.get(options, :header_length, 32 + byte_size(schema))
    record_length = Keyword.get(options, :record_length, 1 + field_length)
    table_flags = Keyword.get(options, :table_flags, 0)
    language_driver = Keyword.get(options, :language_driver, 0)
    records = Keyword.get(options, :records, <<>>)

    header =
      <<version, year, month, day, record_count::little-unsigned-integer-size(32),
        header_length::little-unsigned-integer-size(16),
        record_length::little-unsigned-integer-size(16), 0::size(16), 0, 0, 0::size(96),
        table_flags, language_driver, 0::size(16)>>

    header <> schema <> records
  end

  defp legacy_descriptor(name, type, length, decimal) do
    padded_name = name <> :binary.copy(<<0>>, 11 - byte_size(name))

    padded_name <>
      type <>
      <<0::little-unsigned-integer-size(32), length, decimal>> <>
      :binary.copy(<<0>>, 14)
  end

  def cleanup(path) do
    path |> Path.dirname() |> File.rm_rf!()
    :ok
  end
end
