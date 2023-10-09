defmodule DBF do
  alias DBF.Database, as: DB
  @moduledoc """
  Documentation for `DBF`.
  """

  @doc """
  Hello world.

  ## Examples

      iex> DBF.hello()
      :world

  """
  def hello do
    :world
  end

  def open!(filename) do
    {:ok, file} = File.open(filename, [:read, :binary])
    {:ok, data} = :file.pread(file, 0, 32)

    <<
      version::unsigned-integer-8,
      year::unsigned-integer-8,
      month::unsigned-integer-8,
      day::unsigned-integer-8,
      records::unsigned-integer-32,
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

    %DB{
      device: file,
      version: version,
      last_updated: {year + 1900, month, day},
      number_of_records: records,
      header_bytes: header_length,
      record_bytes: record_length,
      fields: parse_fields(raw_fields)
    }
  end

  def close!(%DBF.Database{device: dev}) do
    File.close(dev)
  end

  defp parse_fields(field_string) do
    parse_fields(field_string, [])
  end

  defp parse_fields(<<
      name::binary-size(11),
      type::binary-size(1),
      _address::unsigned-integer-32,
      length::unsigned-integer-8,
      decimal::unsigned-integer-8,
      _reserved::binary-size(2),
      _work_area::binary-size(1),
      _reserved2::binary-size(2),
      _set_fields_flag::binary-size(1),
      _reserved3::binary-size(8),
      rest::binary
    >>, acc) do
    IO.puts("name: #{String.trim(name, <<0>>)} type: #{type} length: #{length} decimal: #{decimal}")
    parse_fields(rest, [{String.trim(name, <<0>>), type} | acc])
  end
  defp parse_fields(_bang, acc) do
    Enum.reverse(acc)
  end

  def example do
    {:ok, file} = File.open("your_file.txt", [:read, :binary])
    offset = 32  # Starting byte position
    byte_count = 64 - 32 + 1  # Number of bytes to read (inclusive range)

    case :file.pread(file, byte_count, offset) do
      {:ok, data} ->
        IO.puts("Read data: #{inspect(data)}")
      {:error, reason} ->
        IO.puts("Error reading data: #{reason}")
    end

    File.close(file)
  end
end
