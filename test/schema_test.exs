defmodule DBF.SchemaTest do
  use ExUnit.Case, async: true

  alias DBF.FormatProfile
  alias DBF.Header
  alias DBF.Schema

  test "parses complete FoxBase descriptors and preserves their bytes" do
    profile = profile!(0x02)
    descriptor = foxbase_descriptor("NAME", "C", 12)
    header = header(0x02, 8 + byte_size(descriptor) + 1, 13)

    assert {:ok, %Schema{fields: [field], record_length: 13}} =
             Schema.parse(descriptor <> <<0x0D>>, profile, header)

    assert field.name == "NAME"
    assert field.type == "C"
    assert field.length == 12
    assert field.decimal == 0
    assert field.descriptor_offset == 8
    assert field.record_offset == 1
    assert field.raw_descriptor == descriptor
  end

  test "parses complete legacy descriptors and preserves descriptor metadata" do
    profile = profile!(0x03)
    descriptor = legacy_descriptor("AMOUNT", "N", 12, 2, 33, 7, 4)
    header = header(0x03, 32 + byte_size(descriptor) + 1, 13)

    assert {:ok, %Schema{fields: [field], record_length: 13}} =
             Schema.parse(descriptor <> <<0x0D>>, profile, header)

    assert field.name == "AMOUNT"
    assert field.type == "N"
    assert field.length == 12
    assert field.decimal == 2
    assert field.address == 33
    assert field.work_area == 7
    assert field.set_fields_flag == 4
    assert field.descriptor_offset == 32
    assert field.record_offset == 1
    assert field.raw_descriptor == descriptor
  end

  test "compiles each field's physical record offset" do
    profile = profile!(0x03)
    first = legacy_descriptor("FIRST", "C", 3)
    second = legacy_descriptor("SECOND", "C", 5)
    header = header(0x03, 32 + byte_size(first) + byte_size(second) + 1, 9)

    assert {:ok, %Schema{fields: [first_field, second_field]}} =
             Schema.parse(first <> second <> <<0x0D>>, profile, header)

    assert first_field.record_offset == 1
    assert second_field.record_offset == 4
  end

  test "requires the descriptor terminator" do
    profile = profile!(0x03)
    descriptor = legacy_descriptor("NAME", "C", 10)
    header = header(0x03, 32 + byte_size(descriptor), 11)

    assert {:error, %DBF.Error{reason: :invalid_schema, cause: :missing_descriptor_terminator}} =
             Schema.parse(descriptor, profile, header)
  end

  test "rejects record widths that do not equal the field widths plus marker" do
    profile = profile!(0x03)
    descriptor = legacy_descriptor("NAME", "C", 10)
    header = header(0x03, 32 + byte_size(descriptor) + 1, 99)

    assert {:error,
            %DBF.Error{
              reason: :invalid_schema,
              cause: :record_width_mismatch,
              context: %{declared_record_bytes: 99, calculated_record_bytes: 11}
            }} = Schema.parse(descriptor <> <<0x0D>>, profile, header)
  end

  test "rejects FoxBase descriptor truncation at every byte boundary" do
    descriptor = foxbase_descriptor("NAME", "C", 12)
    profile = profile!(0x02)

    for length <- 0..(byte_size(descriptor) - 1) do
      binary = binary_part(descriptor, 0, length)
      header = header(0x02, 8 + length, 13)

      assert {:error, %DBF.Error{reason: :invalid_schema}} =
               Schema.parse(binary, profile, header)
    end
  end

  test "rejects legacy descriptor truncation at every byte boundary" do
    descriptor = legacy_descriptor("NAME", "C", 12)
    profile = profile!(0x03)

    for length <- 0..(byte_size(descriptor) - 1) do
      binary = binary_part(descriptor, 0, length)
      header = header(0x03, 32 + length, 13)

      assert {:error, %DBF.Error{reason: :invalid_schema}} =
               Schema.parse(binary, profile, header)
    end
  end

  defp profile!(version) do
    {:ok, profile} = FormatProfile.select(version)
    profile
  end

  defp header(version, header_length, record_length) do
    %Header{
      version: version,
      date: ~D[2000-01-01],
      record_count: 0,
      header_length: header_length,
      record_length: record_length,
      table_flags: 0,
      language_driver: 0
    }
  end

  defp foxbase_descriptor(name, type, length) do
    pad_name(name) <> type <> <<length>> <> <<0, 0, 0>>
  end

  defp legacy_descriptor(
         name,
         type,
         length,
         decimal \\ 0,
         address \\ 0,
         work_area \\ 0,
         flag \\ 0
       ) do
    pad_name(name) <>
      type <>
      <<address::little-unsigned-integer-size(32), length, decimal, 0, 0, work_area, 0, 0, flag,
        0, 0, 0, 0, 0, 0, 0, 0>>
  end

  defp pad_name(name), do: name <> :binary.copy(<<0>>, 11 - byte_size(name))
end
