defmodule DBF.OpeningSafetyTest do
  use ExUnit.Case

  alias DBF.TestFixture

  test "validates option names, containers, and values before opening a file" do
    missing = "test/dbf_files/does-not-exist.dbf"

    for options <- [
          [unknown: true],
          [memo_file: 123],
          [numeric: :money],
          [encoding: :guess],
          [encoding_errors: :ignore],
          %{memo_file: nil},
          [123]
        ] do
      assert {:error, %DBF.DatabaseError{reason: :invalid_options}} = DBF.open(missing, options)
    end
  end

  test "strict encoding rejects missing or unknown language drivers during opening" do
    for language_driver <- [0, 0xFF] do
      path =
        TestFixture.legacy_dbf(language_driver: language_driver)
        |> TestFixture.write_temp!()

      try do
        assert {:error,
                %DBF.DatabaseError{
                  reason: :invalid_encoding,
                  context: %{language_driver: ^language_driver}
                }} = DBF.open(path, encoding_errors: :strict)
      after
        TestFixture.cleanup(path)
      end
    end
  end

  test "preserves missing-file cause and context and open! raises DatabaseError" do
    path = "test/dbf_files/does-not-exist.dbf"

    assert {:error,
            %DBF.DatabaseError{
              reason: :file_not_found,
              cause: :enoent,
              context: %{filename: ^path, source: :table}
            }} = DBF.open(path)

    assert_raise DBF.DatabaseError, fn -> DBF.open!(path) end
  end

  test "returns contextual errors for truncated structural input" do
    for binary <- [<<>>, <<0x03>>, <<0x03, 124, 1, 1>>] do
      path = TestFixture.write_temp!(binary)

      try do
        assert {:error,
                %DBF.DatabaseError{
                  reason: :invalid_header,
                  context: %{filename: ^path, offset: _offset}
                }} = DBF.open(path)

        assert_raise DBF.DatabaseError, fn -> DBF.open!(path) end
      after
        TestFixture.cleanup(path)
      end
    end
  end

  test "rejects invalid dates, lengths, record bounds, terminators, and widths" do
    cases = [
      {:invalid_header, TestFixture.legacy_dbf(month: 2, day: 30)},
      {:invalid_header, TestFixture.legacy_dbf(header_length: 32)},
      {:invalid_header, TestFixture.legacy_dbf(record_count: 1)},
      {:invalid_schema, TestFixture.legacy_dbf(terminator: false)},
      {:invalid_schema, TestFixture.legacy_dbf(record_length: 99)}
    ]

    for {reason, binary} <- cases do
      path = TestFixture.write_temp!(binary)

      try do
        assert {:error, %DBF.DatabaseError{reason: ^reason, context: %{filename: ^path}}} =
                 DBF.open(path)

        assert_raise DBF.DatabaseError, fn -> DBF.open!(path) end
      after
        TestFixture.cleanup(path)
      end
    end
  end

  test "rejects duplicate decoded field names during opening" do
    assert {:error,
            %DBF.DatabaseError{
              reason: :invalid_schema,
              cause: :duplicate_field_name,
              context: %{field_name: "Point_ID", descriptor_offsets: [32, 992]}
            }} = DBF.open("test/dbf_files/dbase_03.dbf")
  end

  test "preserves structural metadata selected during opening" do
    path =
      TestFixture.legacy_dbf(table_flags: 0x03, language_driver: 0x57)
      |> TestFixture.write_temp!()

    try do
      assert {:ok, db} = DBF.open(path)
      assert db.version == 0x03
      assert db.table_flags == 0x03
      assert db.language_driver == 0x57

      assert [
               %DBF.Field{
                 raw_descriptor: raw,
                 descriptor_offset: 32,
                 record_offset: 1
               }
             ] = db.fields

      assert byte_size(raw) == 32
      assert :ok = DBF.close(db)
    after
      TestFixture.cleanup(path)
    end
  end

  test "a no-memo profile does not guess from an adjacent memo extension" do
    path = TestFixture.legacy_dbf() |> TestFixture.write_temp!("sample.dbf")
    File.write!(Path.rootname(path) <> ".dbt", <<0>>)

    try do
      assert {:ok, db} = DBF.open(path)
      refute DBF.has_memo_file?(db)
      assert :ok = DBF.close(db)
    after
      TestFixture.cleanup(path)
    end
  end

  test "required DBT profiles do not accept an adjacent FPT file" do
    path =
      "test/dbf_files/dbase_83.dbf"
      |> File.read!()
      |> TestFixture.write_temp!("memo-required.dbf")

    File.write!(Path.rootname(path) <> ".fpt", :binary.copy(<<0>>, 512))

    try do
      assert {:error,
              %DBF.DatabaseError{
                reason: :missing_memo_file,
                cause: :enoent,
                context: %{version: 0x83, source: :memo}
              }} = DBF.open(path)
    after
      TestFixture.cleanup(path)
    end
  end

  test "mismatched DBT families fail during opening" do
    assert {:error,
            %DBF.DatabaseError{
              reason: :invalid_memo,
              cause: :mismatched_memo_family,
              context: %{expected_memo_family: :dbt_iii, actual_memo_family: :dbt_iv}
            }} =
             DBF.open("test/dbf_files/dbase_83.dbf",
               memo_file: "test/dbf_files/dbase_8b.dbt"
             )

    assert {:error,
            %DBF.DatabaseError{
              reason: :invalid_memo,
              cause: :invalid_memo_block_signature,
              context: %{memo_block: 1}
            }} =
             DBF.open("test/dbf_files/dbase_8b.dbf",
               memo_file: "test/dbf_files/dbase_83.dbt"
             )
  end

  test "missing, empty, and truncated required memos fail during opening" do
    assert {:error, %DBF.DatabaseError{reason: :missing_memo_file}} =
             DBF.open("test/dbf_files/dbase_83_missing_memo.dbf")

    assert {:error, %DBF.DatabaseError{reason: :missing_memo_file}} =
             DBF.open("test/dbf_files/dbase_83.dbf",
               memo_file: "test/dbf_files/does-not-exist.dbt"
             )

    for {basename, memo} <- [{"empty-memo.dbf", <<>>}, {"truncated-memo.dbf", <<0>>}] do
      path =
        "test/dbf_files/dbase_83.dbf"
        |> File.read!()
        |> TestFixture.write_temp!(basename)

      File.write!(Path.rootname(path) <> ".dbt", memo)

      try do
        assert {:error,
                %DBF.DatabaseError{
                  reason: :invalid_memo,
                  context: %{filename: memo_path, source: :memo, offset: 0}
                }} = DBF.open(path)

        assert memo_path == Path.rootname(path) <> ".dbt"
      after
        TestFixture.cleanup(path)
      end
    end
  end
end
