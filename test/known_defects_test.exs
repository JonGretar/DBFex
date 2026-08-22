defmodule DBF.KnownDefectsTest do
  use ExUnit.Case

  alias DBF.TestFixture

  @moduletag known_defect: true

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
  end
end
