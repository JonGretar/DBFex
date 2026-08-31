defmodule DBF.TextDecoderTest do
  use ExUnit.Case, async: true

  alias DBF.TextDecoder

  test "decodes every name in the CP1251 fixture at the decoder level" do
    binary = File.read!("test/dbf_files/cp1251.dbf")

    <<_::binary-size(4), record_count::little-unsigned-integer-size(32),
      header_length::little-unsigned-integer-size(16),
      record_length::little-unsigned-integer-size(16), _::binary>> = binary

    assert {:ok, decoder} =
             TextDecoder.compile(0xC9, encoding: :auto, encoding_errors: :strict)

    names =
      for index <- 0..(record_count - 1) do
        offset = header_length + index * record_length + 5
        raw_name = binary_part(binary, offset, 100)
        assert {:ok, name} = TextDecoder.decode(decoder, raw_name, :both)
        name
      end

    assert names == [
             "амбулаторно-поликлиническое",
             "больничное",
             "НИИ",
             "образовательное медицинское учреждение"
           ]
  end

  test "decodes Western Windows bytes for both documented driver identifiers" do
    for driver <- [0x03, 0x57] do
      assert {:ok, decoder} =
               TextDecoder.compile(driver, encoding: :auto, encoding_errors: :strict)

      assert {:ok, "€ café"} = TextDecoder.decode(decoder, <<0x80, " caf", 0xE9>>)
    end
  end

  test "applies strict, replacement, and raw policies to undefined bytes" do
    assert {:ok, strict} =
             TextDecoder.compile(0x03, encoding: :auto, encoding_errors: :strict)

    assert {:error, %DBF.Error{reason: :invalid_encoding, cause: :invalid_byte}} =
             TextDecoder.decode(strict, <<0x81>>)

    assert {:ok, replace} =
             TextDecoder.compile(0x03, encoding: :auto, encoding_errors: :replace)

    assert {:ok, "�"} = TextDecoder.decode(replace, <<0x81>>)

    assert {:ok, raw} = TextDecoder.compile(0x03, encoding: :auto, encoding_errors: :raw)
    assert {:ok, <<0x81>>} = TextDecoder.decode(raw, <<0x81>>)
  end

  test "raw fallback returns the complete original byte string" do
    assert {:ok, raw} = TextDecoder.compile(0x03, encoding: :auto, encoding_errors: :raw)

    original = <<0xE9, 0x81, 0xE9>>

    assert {:ok, ^original} = TextDecoder.decode(raw, original)
  end

  test "removes fixed-width padding before raw fallback" do
    assert {:ok, raw} = TextDecoder.compile(0x03, encoding: :auto, encoding_errors: :raw)

    assert {:ok, <<0xE9, 0x81, 0xE9>>} =
             TextDecoder.decode(raw, <<"  ", 0xE9, 0x81, 0xE9, "  ">>, :both)
  end

  test "does not guess missing or unknown language drivers" do
    for driver <- [nil, 0, 0xFF] do
      assert {:ok, raw} =
               TextDecoder.compile(driver, encoding: :auto, encoding_errors: :raw)

      assert {:ok, <<0xFF>>} = TextDecoder.decode(raw, <<0xFF>>)

      assert {:error, %DBF.Error{reason: :invalid_encoding}} =
               TextDecoder.compile(driver, encoding: :auto, encoding_errors: :strict)
    end
  end
end
