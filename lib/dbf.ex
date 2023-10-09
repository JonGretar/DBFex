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
      records::little-signed-integer-32,
      header_length::little-signed-integer-16,
      field_descriptor_length::little-signed-integer-16,
      _rest::binary
    >> = data

    {:ok, raw_fields} = :file.pread(file, 32, field_descriptor_length)

    %DB{
      device: file,
      version: version,
      last_updated: {year + 1900, month, day},
      number_of_records: records,
      header_bytes: header_length,
      fields: parse_fields(raw_fields)
    }
  end

  def close!(%DBF.Database{device: dev}) do
    File.close(dev)
  end

  defp parse_fields(field_string) do
    parse_fields(field_string, [])
  end

  defp parse_fields(<<name::binary-size(11), type::binary-size(1), _bla::binary-size(20), rest::binary>>, acc) do
    IO.puts("name: #{String.trim(name, <<0>>)} type: #{type} ")
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
