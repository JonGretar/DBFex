defmodule DBF.Schema do
  @moduledoc false

  import Bitwise, only: [band: 2]

  alias DBF.Error
  alias DBF.Field
  alias DBF.FieldDescriptorLayout
  alias DBF.FormatProfile
  alias DBF.Header
  alias DBF.TextDecoder
  alias DBF.ValueDecoder

  @enforce_keys [:fields, :record_length, :text_decoder, :backlink]
  defstruct [:fields, :record_length, :text_decoder, :record_bitmap, :backlink]

  @type t :: %__MODULE__{
          fields: [Field.t()],
          record_length: pos_integer(),
          text_decoder: TextDecoder.t(),
          record_bitmap: %{record_offset: pos_integer(), length: pos_integer()} | nil,
          backlink: String.t() | binary() | nil
        }

  @spec parse(binary(), FormatProfile.t(), Header.t(), DBF.options()) ::
          {:ok, t()} | {:error, Error.t()}
  def parse(binary, profile, header, options \\ [])

  def parse(binary, %FormatProfile{} = profile, %Header{} = header, options)
      when is_binary(binary) and is_list(options) do
    descriptor_offset = FieldDescriptorLayout.start(profile.field_descriptor_layout)

    with {:ok, text_decoder} <- TextDecoder.compile(header.language_driver, options),
         :ok <- validate_schema_size(binary, header, descriptor_offset),
         {:ok, fields, descriptor_metadata} <-
           parse_descriptors(
             binary,
             profile.field_descriptor_layout,
             text_decoder,
             descriptor_offset,
             []
           ),
         {:ok, fields, record_bitmap} <- compile_fields(fields, profile, header, options) do
      {:ok,
       %__MODULE__{
         fields: fields,
         record_length: header.record_length,
         text_decoder: text_decoder,
         record_bitmap: record_bitmap,
         backlink: descriptor_metadata.backlink
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
         text_decoder,
         offset,
         fields
       ) do
    case FieldDescriptorLayout.parse_tail(layout, tail) do
      {:ok, %{backlink: backlink}} ->
        with {:ok, backlink} <- decode_backlink(backlink, text_decoder, offset + 1) do
          {:ok, Enum.reverse(fields), %{backlink: backlink}}
        end

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
           autoincrement_next::little-unsigned-integer-size(32), autoincrement_step,
           reserved::binary-size(8)>> = raw,
         :visual_foxpro_32,
         text_decoder,
         offset
       ) do
    with {:ok, name} <- decode_name(raw_name, text_decoder, offset) do
      {autoincrement_next, autoincrement_step} =
        if band(flags, 0x08) == 0x08 do
          {autoincrement_next, autoincrement_step}
        else
          {nil, nil}
        end

      {:ok,
       %Field{
         name: name,
         type: type,
         length: length,
         decimal: decimal,
         address: address,
         flags: flags,
         autoincrement_next: autoincrement_next,
         autoincrement_step: autoincrement_step,
         work_area: nil,
         set_fields_flag: nil,
         descriptor_offset: offset,
         raw_descriptor: raw,
         reserved: reserved
       }}
    end
  end

  defp compile_fields(fields, profile, header, options) do
    with :ok <- validate_field_lengths(fields, profile),
         :ok <- validate_field_widths(fields, profile),
         :ok <- validate_field_scales(fields, profile),
         :ok <- validate_field_flags(fields, profile),
         :ok <- validate_autoincrement(fields, profile) do
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

      compiled = Enum.reverse(compiled)

      with :ok <- validate_unique_names(names),
           :ok <- validate_record_width(record_length, header) do
        compile_record_layout(compiled, profile)
      end
    end
  end

  defp validate_field_lengths(fields, %FormatProfile{
         record_layout: layout
       })
       when layout in [:dbase_legacy, :visual_foxpro_nullable, :visual_foxpro_variable] do
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
    expected_widths = %{
      "B" => 8,
      "G" => 4,
      "I" => 4,
      "M" => 4,
      "P" => 4,
      "T" => 8,
      "W" => 4,
      "Y" => 8
    }

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

  defp validate_field_scales(
         fields,
         %FormatProfile{record_layout: layout}
       ) do
    validate_visual_foxpro_field_scales(fields, layout)
  end

  defp validate_visual_foxpro_field_scales(fields, layout)
       when layout in [:visual_foxpro_nullable, :visual_foxpro_variable] do
    case Enum.find(fields, &(&1.type == "Y" and &1.decimal != 4)) do
      nil ->
        :ok

      field ->
        {:error,
         schema_error(:invalid_field_scale, %{
           field_name: field.name,
           field_type: field.type,
           field_scale: field.decimal,
           expected: 4,
           offset: field.descriptor_offset + 17
         })}
    end
  end

  defp validate_visual_foxpro_field_scales(_fields, _layout), do: :ok

  defp validate_field_flags(
         fields,
         %FormatProfile{record_layout: :visual_foxpro_variable}
       ) do
    case Enum.find(fields, &(not valid_variable_field_flags?(&1))) do
      nil ->
        :ok

      field ->
        unsupported_field_flags(field)
    end
  end

  defp validate_field_flags(
         fields,
         %FormatProfile{record_layout: :visual_foxpro_nullable}
       ) do
    case Enum.find(fields, &(not valid_nullable_field_flags?(&1))) do
      nil ->
        :ok

      field ->
        unsupported_field_flags(field)
    end
  end

  defp validate_field_flags(
         fields,
         %FormatProfile{field_descriptor_layout: :visual_foxpro_32}
       ) do
    case Enum.find(fields, fn field ->
           field.flags != 0x00 and
             not (field.flags == 0x04 and field.type in ["B", "C", "I", "M", "P", "T"])
         end) do
      nil ->
        :ok

      field ->
        unsupported_field_flags(field)
    end
  end

  defp validate_field_flags(_fields, _profile), do: :ok

  defp validate_autoincrement(
         fields,
         %FormatProfile{record_layout: layout}
       ) do
    validate_visual_foxpro_autoincrement(fields, layout)
  end

  defp validate_visual_foxpro_autoincrement(fields, layout)
       when layout in [:visual_foxpro_nullable, :visual_foxpro_variable] do
    case Enum.find(fields, &(&1.autoincrement_step == 0)) do
      nil ->
        :ok

      field ->
        {:error,
         schema_error(:invalid_autoincrement_step, %{
           field_name: field.name,
           autoincrement_step: field.autoincrement_step,
           offset: field.descriptor_offset + 23
         })}
    end
  end

  defp validate_visual_foxpro_autoincrement(_fields, _layout), do: :ok

  defp valid_nullable_field_flags?(%{type: "0", flags: flags}), do: flags == 0x05

  defp valid_nullable_field_flags?(%{type: "I", flags: flags}),
    do: flags in [0x00, 0x02, 0x04, 0x06, 0x0C, 0x0E]

  defp valid_nullable_field_flags?(%{type: type, flags: flags})
       when type in ["B", "C", "M", "P", "T", "W", "Y"],
       do: flags in [0x00, 0x02, 0x04, 0x06]

  defp valid_nullable_field_flags?(%{flags: flags}), do: flags in [0x00, 0x02]

  defp valid_variable_field_flags?(%{type: type, flags: flags}) when type in ["Q", "V"],
    do: flags in [0x00, 0x02, 0x04, 0x06]

  defp valid_variable_field_flags?(field), do: valid_nullable_field_flags?(field)

  defp unsupported_field_flags(field) do
    {:error,
     schema_error(:unsupported_field_flags, %{
       field_name: field.name,
       field_type: field.type,
       field_flags: field.flags,
       offset: field.descriptor_offset + 18
     })}
  end

  defp compile_record_layout(fields, %FormatProfile{record_layout: :dbase_legacy}) do
    {:ok, fields, nil}
  end

  defp compile_record_layout(fields, %FormatProfile{
         record_layout: :visual_foxpro_nullable
       }) do
    compile_record_bitmap(fields, &compile_nullable_field/2)
  end

  defp compile_record_layout(fields, %FormatProfile{
         record_layout: :visual_foxpro_variable
       }) do
    compile_record_bitmap(fields, &compile_variable_field/2)
  end

  defp compile_record_bitmap(fields, compile_field) do
    null_fields = Enum.filter(fields, &(&1.type == "0"))
    {compiled_fields, bit_count} = Enum.map_reduce(fields, 0, compile_field)
    visible_fields = Enum.reject(compiled_fields, &is_nil/1)

    case {null_fields, bit_count} do
      {[], 0} ->
        {:ok, visible_fields, nil}

      {[null_field], bit_count} when bit_count > 0 ->
        validate_record_bitmap(visible_fields, null_field, bit_count)

      {[], _bit_count} ->
        {:error, schema_error(:missing_null_bitmap, %{})}

      {[_ | _], 0} ->
        {:error, schema_error(:unexpected_null_bitmap, %{})}

      {null_fields, _bit_count} ->
        {:error, schema_error(:multiple_null_bitmaps, %{count: length(null_fields)})}
    end
  end

  defp validate_record_bitmap(visible_fields, null_field, bit_count) do
    expected_length = div(bit_count + 7, 8)

    cond do
      null_field.name != "_NullFlags" ->
        {:error,
         schema_error(:invalid_null_bitmap, %{
           field_name: null_field.name,
           expected_name: "_NullFlags"
         })}

      null_field.length != expected_length ->
        {:error,
         schema_error(:invalid_null_bitmap_width, %{
           expected_bytes: expected_length,
           actual_bytes: null_field.length
         })}

      true ->
        {:ok, visible_fields,
         %{record_offset: null_field.record_offset, length: null_field.length}}
    end
  end

  defp compile_nullable_field(%{type: "0"}, bit), do: {nil, bit}

  defp compile_nullable_field(%{flags: flags} = field, bit) when band(flags, 0x02) == 0x02 do
    {%Field{field | null_bit: bit}, bit + 1}
  end

  defp compile_nullable_field(field, bit), do: {field, bit}

  defp compile_variable_field(%{type: type, flags: flags} = field, bit)
       when type in ["Q", "V"] do
    field = %Field{field | variable_length_bit: bit}

    if band(flags, 0x02) == 0x02 do
      {%Field{field | null_bit: bit + 1}, bit + 2}
    else
      {field, bit + 1}
    end
  end

  defp compile_variable_field(field, bit), do: compile_nullable_field(field, bit)

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

  defp decode_backlink(nil, _text_decoder, _offset), do: {:ok, nil}

  defp decode_backlink(raw_backlink, text_decoder, offset) do
    case TextDecoder.decode(text_decoder, raw_backlink, :none) do
      {:ok, decoded} ->
        {:ok, decoded}

      {:error, %Error{} = error} ->
        {:error, Error.add_context(error, %{offset: offset, source: :backlink})}
    end
  end

  defp schema_error(cause, context), do: Error.new(:invalid_schema, cause, context)

  defp byte_size_if_binary(binary) when is_binary(binary), do: byte_size(binary)
  defp byte_size_if_binary(_binary), do: nil
end
