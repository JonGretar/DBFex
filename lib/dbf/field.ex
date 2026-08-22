defmodule DBF.Field do
  @moduledoc """
  Metadata describing a field in a DBF record.
  """

  alias DBF.Error
  alias DBF.FormatProfile
  alias DBF.Header

  defstruct [
    :name,
    :type,
    :length,
    :decimal,
    :address,
    :flags,
    :work_area,
    :set_fields_flag,
    :descriptor_offset,
    :raw_descriptor,
    :reserved
  ]

  @type t :: %__MODULE__{
          name: binary(),
          type: binary(),
          length: non_neg_integer(),
          decimal: non_neg_integer(),
          address: non_neg_integer() | nil,
          flags: byte() | nil,
          work_area: byte() | nil,
          set_fields_flag: byte() | nil,
          descriptor_offset: non_neg_integer(),
          raw_descriptor: binary(),
          reserved: binary()
        }

  @doc false
  @spec parse(binary(), FormatProfile.t(), Header.t()) ::
          {:ok, [t()]} | {:error, Error.t()}
  def parse(binary, %FormatProfile{} = profile, %Header{} = header) when is_binary(binary) do
    descriptor_offset = descriptor_start(profile.field_descriptor_layout)

    with :ok <- validate_schema_size(binary, header, descriptor_offset),
         {:ok, fields} <-
           parse_descriptors(binary, profile.field_descriptor_layout, descriptor_offset, []),
         :ok <- validate_record_width(fields, header) do
      {:ok, fields}
    end
  end

  def parse(binary, profile, header) do
    {:error,
     schema_error(:invalid_schema_input, %{
       actual_bytes: byte_size_if_binary(binary),
       profile: profile,
       header: header
     })}
  end

  defp validate_schema_size(binary, header, descriptor_offset) do
    expected = header.header_length - descriptor_offset
    actual = byte_size(binary)

    cond do
      expected < 1 ->
        {:error,
         schema_error(:invalid_header_length, %{
           header_length: header.header_length,
           descriptor_offset: descriptor_offset,
           offset: descriptor_offset
         })}

      actual != expected ->
        {:error,
         schema_error(:invalid_schema_size, %{
           expected_bytes: expected,
           actual_bytes: actual,
           offset: descriptor_offset + min(actual, expected)
         })}

      true ->
        :ok
    end
  end

  defp parse_descriptors(<<0x0D, _padding::binary>>, _layout, _offset, fields) do
    {:ok, Enum.reverse(fields)}
  end

  defp parse_descriptors(<<>>, _layout, offset, _fields) do
    {:error, schema_error(:missing_descriptor_terminator, %{offset: offset})}
  end

  defp parse_descriptors(binary, layout, offset, fields) do
    size = descriptor_size(layout)

    if byte_size(binary) < size do
      {:error,
       schema_error(:truncated_field_descriptor, %{
         offset: offset,
         expected_bytes: size,
         actual_bytes: byte_size(binary)
       })}
    else
      <<descriptor::binary-size(size), rest::binary>> = binary

      with {:ok, field} <- decode_descriptor(descriptor, layout, offset) do
        parse_descriptors(rest, layout, offset + size, [field | fields])
      end
    end
  end

  # FoxBase descriptor reference:
  # https://www.clicketyclick.dk/databases/xbase/format/index.html
  defp decode_descriptor(
         <<raw_name::binary-size(11), type::binary-size(1), length, reserved::binary-size(3)>> =
           raw,
         :foxbase_16,
         offset
       ) do
    {:ok,
     %__MODULE__{
       name: decode_name(raw_name),
       type: type,
       length: length,
       decimal: 0,
       address: nil,
       flags: nil,
       work_area: nil,
       set_fields_flag: nil,
       descriptor_offset: offset,
       raw_descriptor: raw,
       reserved: reserved
     }}
  end

  # dBASE III/IV descriptor reference:
  # https://blogs.embarcadero.com/dbase-dbf-file-structure/
  defp decode_descriptor(
         <<raw_name::binary-size(11), type::binary-size(1),
           address::little-unsigned-integer-size(32), length, decimal, reserved_1::binary-size(2),
           work_area, reserved_2::binary-size(2), set_fields_flag,
           reserved_3::binary-size(8)>> = raw,
         :dbase_legacy_32,
         offset
       ) do
    {:ok,
     %__MODULE__{
       name: decode_name(raw_name),
       type: type,
       length: length,
       decimal: decimal,
       address: address,
       flags: nil,
       work_area: work_area,
       set_fields_flag: set_fields_flag,
       descriptor_offset: offset,
       raw_descriptor: raw,
       reserved: reserved_1 <> reserved_2 <> reserved_3
     }}
  end

  defp validate_record_width(fields, header) do
    calculated = 1 + Enum.sum(Enum.map(fields, & &1.length))

    if calculated == header.record_length do
      :ok
    else
      {:error,
       schema_error(:record_width_mismatch, %{
         declared_record_bytes: header.record_length,
         calculated_record_bytes: calculated,
         offset: header.header_length
       })}
    end
  end

  defp decode_name(raw_name) do
    name =
      case :binary.match(raw_name, <<0>>) do
        {index, 1} -> binary_part(raw_name, 0, index)
        :nomatch -> raw_name
      end

    trim_trailing_spaces(name)
  end

  defp trim_trailing_spaces(<<>>), do: <<>>

  defp trim_trailing_spaces(binary) do
    if :binary.last(binary) == 0x20 do
      trim_trailing_spaces(binary_part(binary, 0, byte_size(binary) - 1))
    else
      binary
    end
  end

  defp schema_error(cause, context), do: Error.new(:invalid_schema, cause, context)

  defp descriptor_start(:foxbase_16), do: 8
  defp descriptor_start(:dbase_legacy_32), do: 32

  defp descriptor_size(:foxbase_16), do: 16
  defp descriptor_size(:dbase_legacy_32), do: 32

  defp byte_size_if_binary(binary) when is_binary(binary), do: byte_size(binary)
  defp byte_size_if_binary(_binary), do: nil
end
