defmodule DBF.Schema do
  @moduledoc false

  alias DBF.Error
  alias DBF.Field
  alias DBF.FieldDescriptorLayout
  alias DBF.FormatProfile
  alias DBF.Header
  alias DBF.TextDecoder
  alias DBF.ValueDecoder

  @enforce_keys [:fields, :record_length, :text_decoder]
  defstruct [:fields, :record_length, :text_decoder]

  @type t :: %__MODULE__{
          fields: [Field.t()],
          record_length: pos_integer(),
          text_decoder: TextDecoder.t()
        }

  @spec parse(binary(), FormatProfile.t(), Header.t(), DBF.options()) ::
          {:ok, t()} | {:error, Error.t()}
  def parse(binary, profile, header, options \\ [])

  def parse(binary, %FormatProfile{} = profile, %Header{} = header, options)
      when is_binary(binary) and is_list(options) do
    descriptor_offset = FieldDescriptorLayout.start(profile.field_descriptor_layout)

    with {:ok, text_decoder} <- TextDecoder.compile(header.language_driver, options),
         :ok <- validate_schema_size(binary, header, descriptor_offset),
         {:ok, fields} <-
           parse_descriptors(
             binary,
             profile.field_descriptor_layout,
             text_decoder,
             descriptor_offset,
             []
           ),
         {:ok, fields} <- compile_fields(fields, profile, header, options) do
      {:ok,
       %__MODULE__{
         fields: fields,
         record_length: header.record_length,
         text_decoder: text_decoder
       }}
    end
  end

  def parse(binary, profile, header, _options) do
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

  defp parse_descriptors(
         <<0x0D, tail::binary>>,
         layout,
         _text_decoder,
         offset,
         fields
       ) do
    case FieldDescriptorLayout.validate_tail(layout, tail) do
      :ok ->
        {:ok, Enum.reverse(fields)}

      {:error, cause, context} ->
        {:error, schema_error(cause, Map.put(context, :offset, offset + 1))}
    end
  end

  defp parse_descriptors(<<>>, _layout, _text_decoder, offset, _fields) do
    {:error, schema_error(:missing_descriptor_terminator, %{offset: offset})}
  end

  defp parse_descriptors(binary, layout, text_decoder, offset, fields) do
    size = FieldDescriptorLayout.size(layout)

    if byte_size(binary) < size do
      {:error,
       schema_error(:truncated_field_descriptor, %{
         offset: offset,
         expected_bytes: size,
         actual_bytes: byte_size(binary)
       })}
    else
      <<descriptor::binary-size(size), rest::binary>> = binary

      with {:ok, field} <- decode_descriptor(descriptor, layout, text_decoder, offset) do
        parse_descriptors(rest, layout, text_decoder, offset + size, [field | fields])
      end
    end
  end

  # FoxBase descriptor reference:
  # https://www.clicketyclick.dk/databases/xbase/format/index.html
  defp decode_descriptor(
         <<raw_name::binary-size(11), type::binary-size(1), length, reserved::binary-size(3)>> =
           raw,
         :foxbase_16,
         text_decoder,
         offset
       ) do
    with {:ok, name} <- decode_name(raw_name, text_decoder, offset) do
      {:ok,
       %Field{
         name: name,
         type: type,
         length: length,
         decimal: nil,
         address: nil,
         flags: nil,
         work_area: nil,
         set_fields_flag: nil,
         descriptor_offset: offset,
         raw_descriptor: raw,
         reserved: reserved
       }}
    end
  end

  # dBASE III/IV descriptor reference:
  # https://blogs.embarcadero.com/dbase-dbf-file-structure/
  defp decode_descriptor(
         <<raw_name::binary-size(11), type::binary-size(1),
           address::little-unsigned-integer-size(32), length, decimal, reserved_1::binary-size(2),
           work_area, reserved_2::binary-size(2), set_fields_flag,
           reserved_3::binary-size(8)>> = raw,
         :dbase_legacy_32,
         text_decoder,
         offset
       ) do
    with {:ok, name} <- decode_name(raw_name, text_decoder, offset) do
      {:ok,
       %Field{
         name: name,
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
  end

  # Visual FoxPro field descriptor:
  # https://learn.microsoft.com/en-us/previous-versions/visualstudio/foxpro/st4a0s68(v=vs.71)
  defp decode_descriptor(
         <<raw_name::binary-size(11), type::binary-size(1),
           address::little-unsigned-integer-size(32), length, decimal, flags,
           autoincrement::binary-size(5), reserved::binary-size(8)>> = raw,
         :visual_foxpro_32,
         text_decoder,
         offset
       ) do
    with {:ok, name} <- decode_name(raw_name, text_decoder, offset) do
      {:ok,
       %Field{
         name: name,
         type: type,
         length: length,
         decimal: decimal,
         address: address,
         flags: flags,
         work_area: nil,
         set_fields_flag: nil,
         descriptor_offset: offset,
         raw_descriptor: raw,
         reserved: autoincrement <> reserved
       }}
    end
  end

  defp compile_fields(fields, profile, header, options) do
    with :ok <- validate_field_lengths(fields, profile),
         :ok <- validate_field_widths(fields, profile),
         :ok <- validate_field_flags(fields, profile) do
      {compiled, record_length, names} =
        Enum.reduce(fields, {[], 1, %{}}, fn field, {compiled, offset, names} ->
          compiled_field = %Field{
            field
            | record_offset: offset,
              decoder: ValueDecoder.compile(field, profile, options)
          }

          descriptor_offsets = Map.get(names, field.name, [])

          {
            [compiled_field | compiled],
            offset + field.length,
            Map.put(names, field.name, [field.descriptor_offset | descriptor_offsets])
          }
        end)

      with :ok <- validate_unique_names(names),
           :ok <- validate_record_width(record_length, header) do
        {:ok, Enum.reverse(compiled)}
      end
    end
  end

  defp validate_field_lengths(fields, %FormatProfile{record_layout: :dbase_legacy}) do
    case Enum.find(fields, &(&1.length < 1)) do
      nil ->
        :ok

      field ->
        {:error,
         schema_error(:invalid_field_length, %{
           field_name: field.name,
           field_type: field.type,
           field_length: field.length,
           minimum: 1,
           offset: field.descriptor_offset
         })}
    end
  end

  defp validate_field_widths(
         fields,
         %FormatProfile{field_descriptor_layout: :visual_foxpro_32}
       ) do
    expected_widths = %{"I" => 4, "M" => 4, "T" => 8}

    case Enum.find(fields, &invalid_field_width?(&1, expected_widths)) do
      nil ->
        :ok

      field ->
        {:error,
         schema_error(:invalid_field_length, %{
           field_name: field.name,
           field_type: field.type,
           field_length: field.length,
           expected: Map.fetch!(expected_widths, field.type),
           offset: field.descriptor_offset + 16
         })}
    end
  end

  defp validate_field_widths(_fields, _profile), do: :ok

  defp invalid_field_width?(field, expected_widths) do
    case Map.fetch(expected_widths, field.type) do
      {:ok, expected} -> field.length != expected
      :error -> false
    end
  end

  defp validate_field_flags(
         fields,
         %FormatProfile{field_descriptor_layout: :visual_foxpro_32}
       ) do
    case Enum.find(fields, fn field ->
           field.flags != 0x00 and not (field.flags == 0x04 and field.type in ["I", "T"])
         end) do
      nil ->
        :ok

      field ->
        {:error,
         schema_error(:unsupported_field_flags, %{
           field_name: field.name,
           field_type: field.type,
           field_flags: field.flags,
           offset: field.descriptor_offset + 18
         })}
    end
  end

  defp validate_field_flags(_fields, _profile), do: :ok

  defp validate_unique_names(names) do
    case Enum.find(names, fn {_name, offsets} -> length(offsets) > 1 end) do
      nil ->
        :ok

      {name, offsets} ->
        {:error,
         schema_error(:duplicate_field_name, %{
           field_name: name,
           descriptor_offsets: Enum.reverse(offsets)
         })}
    end
  end

  defp validate_record_width(calculated, header) do
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

  defp decode_name(raw_name, text_decoder, descriptor_offset) do
    name =
      case :binary.match(raw_name, <<0>>) do
        {index, 1} -> binary_part(raw_name, 0, index)
        :nomatch -> raw_name
      end

    case TextDecoder.decode(text_decoder, name, :trailing) do
      {:ok, decoded} ->
        {:ok, decoded}

      {:error, %Error{} = error} ->
        {:error, Error.add_context(error, %{offset: descriptor_offset, source: :field_name})}
    end
  end

  defp schema_error(cause, context), do: Error.new(:invalid_schema, cause, context)

  defp byte_size_if_binary(binary) when is_binary(binary), do: byte_size(binary)
  defp byte_size_if_binary(_binary), do: nil
end
