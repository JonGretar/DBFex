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
end
