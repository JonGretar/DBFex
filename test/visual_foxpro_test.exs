defmodule DBF.VisualFoxProTest do
  use ExUnit.Case

  alias DBF.TestFixture

  test "decodes the CP1251 fixture through the public reader" do
    DBF.with_open("test/dbf_files/cp1251.dbf", [encoding_errors: :strict], fn db ->
      assert Enum.to_list(db) == [
               {:record, %{"RN" => 1.0, "NAME" => "амбулаторно-поликлиническое"}},
               {:record, %{"RN" => 2.0, "NAME" => "больничное"}},
               {:record, %{"RN" => 3.0, "NAME" => "НИИ"}},
               {:record, %{"RN" => 4.0, "NAME" => "образовательное медицинское учреждение"}}
             ]
    end)
  end

  test "decodes fixed-width integers" do
    DBF.with_open("test/dbf_files/foxprodb/setup.dbf", fn db ->
      assert Enum.to_list(db) == [
               {:record, %{"KEY_NAME" => "CALLS", "VALUE" => 21}},
               {:record, %{"KEY_NAME" => "CONTACTS", "VALUE" => 8}},
               {:record, %{"KEY_NAME" => "CONTACT_TYPES", "VALUE" => 2}}
             ]
    end)
  end

  test "decodes timestamps and binary FPT pointers" do
    DBF.with_open("test/dbf_files/foxprodb/calls.dbf", fn db ->
      assert Enum.find(db.fields, &(&1.name == "CALL_DATE")).flags == 0x04

      assert {:record,
              %{
                "CALL_ID" => 1,
                "CALL_DATE" => ~N[1994-11-21 13:35:39.000],
                "CALL_TIME" => ~N[1899-12-30 13:35:38.999],
                "NOTES" => notes
              }} = DBF.get(db, 0)

      assert notes ==
               "Nancy told me about their blends. Thinking about it. Should call back later."
    end)
  end

  test "preserves Visual FoxPro table, code-page, field, and backlink metadata" do
    DBF.with_open("test/dbf_files/foxprodb/calls.dbf", fn db ->
      assert db.table_flags == 0x03
      assert db.language_driver == 0x03
      assert db.schema.backlink == "foxpro-db-test.dbc"
      assert Enum.find(db.fields, &(&1.name == "CALL_ID")).flags == 0x04
    end)

    DBF.with_open("test/dbf_files/dbase_30.dbf", fn db ->
      assert db.schema.backlink == nil
    end)
  end

  test "preserves Visual FoxPro Picture memo payloads as binaries" do
    payload = <<0x00, 0xFF, 0x80, "picture data">>

    with_visual_foxpro_memo("P", payload, fn db ->
      assert {:record, %{"VALUE" => ^payload}} = DBF.get(db, 0)
    end)
  end

  test "rejects a text FPT block referenced by a binary memo field" do
    error =
      assert_raise DBF.DatabaseError, fn ->
        with_visual_foxpro_memo("P", "not binary", fn _db -> :ok end, block_type: 1)
      end

    assert error.reason == :invalid_memo
    assert error.cause == :unsupported_memo_block_type
    assert error.context.block_type == 1
    assert error.context.expected_block_type == 0
  end

  test "decodes Visual FoxPro autoincrement tables and exact currency values" do
    assert :ok =
             DBF.with_open("test/dbf_files/dbase_31.dbf", fn db ->
               assert length(db.fields) == 10
               refute Enum.any?(db.fields, &(&1.name == "_NullFlags"))

               assert %{
                        autoincrement_next: 78,
                        autoincrement_step: 1,
                        flags: 0x0C,
                        reserved: <<0::size(64)>>
                      } = Enum.find(db.fields, &(&1.name == "PRODUCTID"))

               assert {:record,
                       %{
                         "PRODUCTID" => 1,
                         "PRODUCTNAM" => "Chai",
                         "UNITPRICE" => %Decimal{} = price
                       }} = DBF.get(db, 0)

               assert Decimal.equal?(price, Decimal.new("18.0000"))
               assert Enum.count(db) == 77
               :ok
             end)
  end

  test "applies the Visual FoxPro null bitmap without exposing its system field" do
    binary = File.read!("test/dbf_files/dbase_31.dbf")
    null_flags_offset = 648 + 94
    <<prefix::binary-size(null_flags_offset), _null_flags, rest::binary>> = binary
    path = TestFixture.write_temp!(prefix <> <<0x01>> <> rest, "nullable-record.dbf")

    try do
      assert {:record, record} =
               DBF.with_open(path, fn db ->
                 refute Enum.any?(db.fields, &(&1.name == "_NullFlags"))
                 DBF.get(db, 0)
               end)

      assert Map.has_key?(record, "SUPPLIERID")
      assert record["SUPPLIERID"] == nil
      assert record["CATEGORYID"] == 1
    after
      TestFixture.cleanup(path)
    end
  end

  test "decodes signed currency storage with four fixed decimal places" do
    binary = File.read!("test/dbf_files/dbase_31.dbf")
    unit_price_offset = 648 + 73
    <<prefix::binary-size(unit_price_offset), _price::binary-size(8), rest::binary>> = binary
    path = TestFixture.write_temp!(prefix <> <<-123_456::little-signed-size(64)>> <> rest)

    try do
      assert {:record, %{"UNITPRICE" => price}} =
               DBF.with_open(path, &DBF.get(&1, 0))

      assert Decimal.equal?(price, Decimal.new("-12.3456"))
    after
      TestFixture.cleanup(path)
    end
  end

  test "rejects null bitmaps that cannot represent every nullable field" do
    binary = File.read!("test/dbf_files/dbase_31.dbf")
    product_name_flags_offset = 64 + 18
    discontinued_flags_offset = 320 + 18
    between_flags = discontinued_flags_offset - product_name_flags_offset - 1

    <<prefix::binary-size(product_name_flags_offset), _product_name_flags,
      middle::binary-size(between_flags), _discontinued_flags, rest::binary>> = binary

    path = TestFixture.write_temp!(prefix <> <<0x02>> <> middle <> <<0x02>> <> rest)

    try do
      assert {:error,
              %DBF.DatabaseError{
                reason: :invalid_schema,
                cause: :invalid_null_bitmap_width,
                context: %{expected_bytes: 2, actual_bytes: 1}
              }} = DBF.open(path)
    after
      TestFixture.cleanup(path)
    end
  end

  test "rejects currency descriptors without the format-defined scale" do
    binary = File.read!("test/dbf_files/dbase_31.dbf")
    unit_price_scale_offset = 192 + 17
    <<prefix::binary-size(unit_price_scale_offset), _scale, rest::binary>> = binary
    path = TestFixture.write_temp!(prefix <> <<2>> <> rest)

    try do
      assert {:error,
              %DBF.DatabaseError{
                reason: :invalid_schema,
                cause: :invalid_field_scale,
                context: %{field_name: "UNITPRICE", field_scale: 2, expected: 4}
              }} = DBF.open(path)
    after
      TestFixture.cleanup(path)
    end
  end

  test "rejects a zero autoincrement step during schema compilation" do
    binary = File.read!("test/dbf_files/dbase_31.dbf")
    autoincrement_step_offset = 32 + 23
    <<prefix::binary-size(autoincrement_step_offset), _step, rest::binary>> = binary
    path = TestFixture.write_temp!(prefix <> <<0>> <> rest, "invalid-autoincrement.dbf")

    try do
      assert {:error,
              %DBF.DatabaseError{
                reason: :invalid_schema,
                cause: :invalid_autoincrement_step,
                context: %{field_name: "PRODUCTID", autoincrement_step: 0}
              }} = DBF.open(path)
    after
      TestFixture.cleanup(path)
    end
  end

  test "decodes Visual FoxPro variable-width binary fields" do
    assert :ok =
             DBF.with_open("test/dbf_files/dbase_32.dbf", fn db ->
               assert length(db.fields) == 1
               refute Enum.any?(db.fields, &(&1.name == "_NullFlags"))
               assert {:record, %{"NAME" => "Bad Meets Evil"}} = DBF.get(db, 0)
               assert Enum.count(db) == 1
               :ok
             end)
  end

  test "decodes VFP 9 binary and variable fields from a producer-generated fixture" do
    memo = for index <- 0..639, into: <<>>, do: <<rem(index, 251)>>
    blob = for index <- 0..699, into: <<>>, do: <<255 - rem(index, 251)>>

    DBF.with_open("test/dbf_files/vfp9_binary.dbf", fn db ->
      assert db.version == 0x32
      assert db.memo_file.block_size == 64

      assert Enum.map(db.fields, &{&1.name, &1.decoder, &1.variable_length_bit, &1.null_bit}) ==
               [
                 {"ID", {:binary, :integer}, nil, 0},
                 {"V_TEXT", {:text, :varchar}, 1, 2},
                 {"Q_BYTES", {:binary, :varbinary}, 3, 4},
                 {"C_BYTES", {:binary, :binary_character}, nil, 5},
                 {"M_BYTES", {:binary, :binary_memo}, nil, 6},
                 {"W_BYTES", {:binary, :binary_memo}, nil, 7},
                 {"B_VALUE", {:binary, :double}, nil, 8}
               ]

      assert {:record,
              %{
                "ID" => 1,
                "V_TEXT" => "text with tail ",
                "Q_BYTES" => <<0x00, 0x20, 0x80, 0xFF, 0x41>>,
                "C_BYTES" => <<0x00, 0xFF, 0x20, 0x80, 0x42>> <> padding,
                "M_BYTES" => ^memo,
                "W_BYTES" => ^blob,
                "B_VALUE" => -12_345.625
              }} = DBF.get(db, 0)

      assert padding == :binary.copy(" ", 15)

      assert {:deleted_record,
              %{
                "ID" => 2,
                "V_TEXT" => "12345678901234567890",
                "Q_BYTES" => sequence,
                "M_BYTES" => nil,
                "W_BYTES" => nil,
                "B_VALUE" => 1.25
              }} = DBF.get(db, 1)

      assert sequence == :binary.list_to_bin(Enum.to_list(0..19))

      assert {:record,
              %{
                "ID" => 3,
                "V_TEXT" => nil,
                "Q_BYTES" => nil,
                "C_BYTES" => nil,
                "M_BYTES" => nil,
                "W_BYTES" => nil,
                "B_VALUE" => nil
              }} = DBF.get(db, 2)

      assert {:record, empty_record} = DBF.get(db, 3)
      assert empty_record["ID"] == 4
      assert empty_record["V_TEXT"] == ""
      assert empty_record["Q_BYTES"] == <<>>
      assert empty_record["M_BYTES"] == nil
      assert empty_record["W_BYTES"] == nil
      assert empty_record["B_VALUE"] == 0.0

      assert empty_record["C_BYTES"] == :binary.copy(" ", 20)
    end)
  end

  test "decodes variable-width text after applying its stored byte length" do
    binary = File.read!("test/dbf_files/dbase_32.dbf")
    field_flags_offset = 32 + 18
    record_value_offset = 360 + 1

    binary = replace_byte(binary, field_flags_offset, 0x00)
    value = <<0xE9>> <> :binary.copy(" ", 248) <> <<1>>
    <<prefix::binary-size(record_value_offset), _value::binary-size(250), rest::binary>> = binary
    path = TestFixture.write_temp!(prefix <> value <> rest)

    try do
      assert {:record, %{"NAME" => "é"}} =
               DBF.with_open(path, [encoding_errors: :strict], &DBF.get(&1, 0))
    after
      TestFixture.cleanup(path)
    end
  end

  test "keeps variable-width binary bytes out of the text decoder" do
    binary = File.read!("test/dbf_files/dbase_32.dbf")
    record_value_offset = 360 + 1
    value = <<0xFF>> <> :binary.copy(<<0>>, 248) <> <<1>>
    <<prefix::binary-size(record_value_offset), _value::binary-size(250), rest::binary>> = binary
    path = TestFixture.write_temp!(prefix <> value <> rest)

    try do
      assert {:record, %{"NAME" => <<0xFF>>}} =
               DBF.with_open(path, [encoding_errors: :strict], &DBF.get(&1, 0))
    after
      TestFixture.cleanup(path)
    end
  end

  test "applies a variable field's null bit before its stored length" do
    binary =
      "test/dbf_files/dbase_32.dbf"
      |> File.read!()
      |> replace_byte(32 + 18, 0x06)
      |> replace_byte(360 + 250, 0xFF)
      |> replace_byte(360 + 251, 0x03)

    path = TestFixture.write_temp!(binary)

    try do
      assert {:record, %{"NAME" => nil}} =
               DBF.with_open(path, &DBF.get(&1, 0))
    after
      TestFixture.cleanup(path)
    end
  end

  test "rejects a stored variable length larger than its physical value area" do
    binary =
      "test/dbf_files/dbase_32.dbf"
      |> File.read!()
      |> replace_byte(360 + 250, 250)

    path = TestFixture.write_temp!(binary)

    try do
      assert {:error,
              %DBF.DatabaseError{
                reason: :invalid_record,
                cause: :invalid_variable_length,
                context: %{field_name: "NAME", value_length: 250, maximum: 249}
              }} = DBF.with_open(path, &DBF.get(&1, 0))
    after
      TestFixture.cleanup(path)
    end
  end

  test "uses the complete physical field when its variable-length bit is clear" do
    binary = File.read!("test/dbf_files/dbase_32.dbf")
    record_value_offset = 360 + 1
    full_value = :binary.copy("A", 250)

    <<prefix::binary-size(record_value_offset), _value::binary-size(250), _bitmap, rest::binary>> =
      binary

    path = TestFixture.write_temp!(prefix <> full_value <> <<0>> <> rest)

    try do
      assert {:record, %{"NAME" => ^full_value}} =
               DBF.with_open(path, &DBF.get(&1, 0))
    after
      TestFixture.cleanup(path)
    end
  end

  test "rejects a variable field without its system record bitmap" do
    binary =
      "test/dbf_files/dbase_32.dbf"
      |> File.read!()
      |> replace_byte(64 + 11, ?C)
      |> replace_byte(64 + 18, 0x00)

    path = TestFixture.write_temp!(binary)

    try do
      assert {:error,
              %DBF.DatabaseError{
                reason: :invalid_schema,
                cause: :missing_null_bitmap
              }} = DBF.open(path)
    after
      TestFixture.cleanup(path)
    end
  end

  test "rejects missing Visual FoxPro backlink storage" do
    <<prefix::binary-size(8), _header_length::binary-size(2), header_rest::binary-size(87),
      _backlink::binary-size(263),
      records::binary>> =
      File.read!("test/dbf_files/cp1251.dbf")

    binary =
      prefix <>
        <<97::little-unsigned-integer-size(16)>> <>
        header_rest <>
        records

    path = TestFixture.write_temp!(binary, "missing-backlink.dbf")

    try do
      assert {:error,
              %DBF.DatabaseError{
                reason: :invalid_schema,
                cause: :invalid_descriptor_tail
              }} = DBF.open(path)
    after
      TestFixture.cleanup(path)
    end
  end

  test "rejects nullable fields until null bitmaps are supported" do
    <<prefix::binary-size(50), _flags, rest::binary>> =
      File.read!("test/dbf_files/cp1251.dbf")

    path = TestFixture.write_temp!(prefix <> <<0x02>> <> rest, "nullable.dbf")

    try do
      assert {:error,
              %DBF.DatabaseError{
                reason: :invalid_schema,
                cause: :unsupported_field_flags,
                context: %{field_name: "RN", field_flags: 0x02}
              }} = DBF.open(path)
    after
      TestFixture.cleanup(path)
    end
  end

  test "rejects invalid fixed binary field widths during schema compilation" do
    <<prefix::binary-size(80), _integer_width, rest::binary>> =
      File.read!("test/dbf_files/foxprodb/setup.dbf")

    path = TestFixture.write_temp!(prefix <> <<5>> <> rest, "wide-integer.dbf")

    try do
      assert {:error,
              %DBF.DatabaseError{
                reason: :invalid_schema,
                cause: :invalid_field_length,
                context: %{
                  field_name: "VALUE",
                  field_type: "I",
                  field_length: 5,
                  expected: 4
                }
              }} = DBF.open(path)
    after
      TestFixture.cleanup(path)
    end
  end

  defp replace_byte(binary, offset, replacement) do
    <<prefix::binary-size(offset), _byte, rest::binary>> = binary
    prefix <> <<replacement>> <> rest
  end

  defp with_visual_foxpro_memo(field_type, payload, fun, options \\ []) do
    block_size = 64
    block_number = 8
    block_type = Keyword.get(options, :block_type, 0)
    next_block = block_number + div(byte_size(payload) + 8 + block_size - 1, block_size)

    memo_header =
      <<next_block::big-unsigned-integer-size(32), 0::size(16),
        block_size::big-unsigned-integer-size(16)>> <> :binary.copy(<<0>>, 504)

    memo_block =
      <<block_type::big-unsigned-integer-size(32),
        byte_size(payload)::big-unsigned-integer-size(32)>> <> payload

    memo =
      (memo_header <> memo_block)
      |> then(&(&1 <> :binary.copy(<<0>>, next_block * block_size - byte_size(&1))))

    field_name = "VALUE" <> :binary.copy(<<0>>, 6)

    descriptor =
      field_name <>
        field_type <>
        <<0::little-unsigned-integer-size(32), 4, 0, 0>> <>
        :binary.copy(<<0>>, 13)

    header_length = 32 + 32 + 1 + 263

    header =
      <<0x30, 124, 1, 1, 1::little-unsigned-integer-size(32),
        header_length::little-unsigned-integer-size(16), 5::little-unsigned-integer-size(16),
        0::size(128), 0x02, 0x03, 0::size(16)>>

    table =
      header <>
        descriptor <>
        <<0x0D>> <>
        :binary.copy(<<0>>, 263) <>
        <<" ", block_number::little-unsigned-integer-size(32)>>

    path = TestFixture.write_temp!(table, "binary-memo.dbf")
    File.write!(Path.rootname(path) <> ".fpt", memo)

    try do
      db = DBF.open!(path)

      try do
        fun.(db)
      after
        DBF.close(db)
      end
    after
      TestFixture.cleanup(path)
    end
  end
end
