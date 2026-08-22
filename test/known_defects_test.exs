defmodule DBF.KnownDefectsTest do
  use ExUnit.Case

  alias DBF.TestFixture

  @moduletag known_defect: true

  describe "Phase 1 failure-safe opening" do
    test "options are validated before opening the DBF" do
      assert {:error, %DBF.DatabaseError{reason: :invalid_options}} =
               DBF.open("test/dbf_files/does-not-exist.dbf", unknown: true)
    end

    test "invalid option values return a database error" do
      assert {:error, %DBF.DatabaseError{reason: :invalid_options}} =
               DBF.open("test/dbf_files/bayarea_zipcodes.dbf", memo_file: 123)
    end

    test "open! raises only DatabaseError for a missing file" do
      assert_raise DBF.DatabaseError, fn ->
        DBF.open!("test/dbf_files/does-not-exist.dbf")
      end
    end

    test "a required missing memo fails during opening" do
      assert {:error, %DBF.DatabaseError{reason: :missing_memo_file}} =
               DBF.open("test/dbf_files/dbase_83_missing_memo.dbf")
    end

    test "truncated inputs return contextual database errors" do
      for {binary, expected_reason} <- [
            {<<>>, :invalid_header},
            {<<0x03>>, :invalid_header},
            {<<0x03, 124, 1, 1>>, :invalid_header}
          ] do
        path = TestFixture.write_temp!(binary)

        try do
          assert {:error, %DBF.DatabaseError{reason: ^expected_reason}} = DBF.open(path)
        after
          TestFixture.cleanup(path)
        end
      end
    end
  end

  describe "Phase 2 structural record correctness" do
    setup do
      db = DBF.open!("test/dbf_files/bayarea_zipcodes.dbf")
      on_exit(fn -> DBF.close(db) end)
      %{db: db}
    end

    test "negative and non-integer record indexes return database errors", %{db: db} do
      for index <- [-1, 0.5, "0"] do
        assert {:error, %DBF.DatabaseError{reason: :invalid_record_index}} = DBF.get(db, index)
      end
    end

    test "out-of-range indexes use the same error category", %{db: db} do
      assert {:error, %DBF.DatabaseError{reason: :invalid_record_index}} = DBF.get(db, 187)
    end

    test "unknown record markers return an invalid-record error" do
      path =
        TestFixture.with_record_marker!("test/dbf_files/bayarea_zipcodes.dbf", 0, "?")

      try do
        db = DBF.open!(path)

        try do
          assert {:error, %DBF.DatabaseError{reason: :invalid_record}} = DBF.get(db, 0)
        after
          DBF.close(db)
        end
      after
        TestFixture.cleanup(path)
      end
    end

    test "duplicate field names fail schema parsing instead of overwriting values" do
      assert {:error, %DBF.DatabaseError{reason: :invalid_schema}} =
               DBF.open("test/dbf_files/dbase_03.dbf")
    end
  end
end
