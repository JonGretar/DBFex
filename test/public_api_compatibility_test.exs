defmodule DBF.PublicAPICompatibilityTest do
  use ExUnit.Case

  alias DBF.TestFixture

  @zipcodes "test/dbf_files/bayarea_zipcodes.dbf"
  @dbase3_memo "test/dbf_files/dbase_83.dbf"
  @dbase3_memo_file "test/dbf_files/dbase_83.dbt"

  describe "opening and closing" do
    test "open/1 and open/2 return an open database" do
      assert {:ok, db1} = DBF.open(@zipcodes)
      assert :ok = DBF.close(db1)

      assert {:ok, db2} = DBF.open(@zipcodes, [])
      assert :ok = DBF.close(db2)
    end

    test "open!/1 and open!/2 return an open database" do
      db1 = DBF.open!(@zipcodes)
      assert :ok = DBF.close(db1)

      db2 = DBF.open!(@zipcodes, [])
      assert :ok = DBF.close(db2)
    end

    test "an explicit memo path is accepted" do
      assert {:ok, db} = DBF.open(@dbase3_memo, memo_file: @dbase3_memo_file)
      assert DBF.has_memo_file?(db)
      assert {:record, %{"DESC" => description}} = DBF.get(db, 0)
      assert is_binary(description)
      assert :ok = DBF.close(db)
    end

    test "unsupported versions use the public error tuple" do
      assert {:error,
              %DBF.DatabaseError{
                reason: :unsupported_version,
                further_info: "FoxPro with memo file"
              }} = DBF.open("test/dbf_files/dbase_f5.dbf")

      assert_raise DBF.DatabaseError, fn ->
        DBF.open!("test/dbf_files/dbase_f5.dbf")
      end
    end
  end

  describe "record access" do
    setup do
      db = DBF.open!(@zipcodes)
      on_exit(fn -> DBF.close(db) end)
      %{db: db}
    end

    test "record indexes are zero-based and preserve the public tuple shape", %{db: db} do
      assert {:record, first} = DBF.get(db, 0)
      assert is_map(first)
      assert {:record, last} = DBF.get(db, 186)
      assert is_map(last)
    end

    test "an index at or above the physical count is rejected", %{db: db} do
      assert {:error, :record_not_found} = DBF.get(db, 187)
      assert {:error, :record_not_found} = DBF.get(db, 999)
    end

    test "deleted records preserve their values and status", %{db: db} do
      path = TestFixture.with_record_marker!(@zipcodes, 0, "*")
      on_exit(fn -> TestFixture.cleanup(path) end)

      deleted_db = DBF.open!(path)
      on_exit(fn -> DBF.close(deleted_db) end)

      assert {:record, expected} = DBF.get(db, 0)
      assert {:deleted_record, ^expected} = DBF.get(deleted_db, 0)
    end
  end

  describe "Enumerable" do
    setup do
      db = DBF.open!(@zipcodes)
      on_exit(fn -> DBF.close(db) end)
      %{db: db}
    end

    test "count reports the physical record count", %{db: db} do
      assert {:ok, 187} = Enumerable.count(db)
      assert 187 = Enum.count(db)
    end

    test "reduce preserves file order and completes", %{db: db} do
      assert {:done, records} =
               Enumerable.reduce(db, {:cont, []}, fn record, records ->
                 {:cont, [record | records]}
               end)

      assert 187 = length(records)
      assert DBF.get(db, 0) == List.last(records)
    end

    test "halt returns without reading a record", %{db: db} do
      assert {:halted, :stopped} =
               Enumerable.reduce(db, {:halt, :stopped}, fn _, _ ->
                 flunk("the reducer must not run")
               end)

      assert [DBF.get(db, 0)] == Enum.take(db, 1)
    end

    test "suspend returns a resumable continuation", %{db: db} do
      reducer = fn record, records -> {:suspend, [record | records]} end

      assert {:suspended, [first], continuation} =
               Enumerable.reduce(db, {:cont, []}, reducer)

      assert first == DBF.get(db, 0)
      assert {:suspended, [second], next_continuation} = continuation.({:cont, []})
      assert second == DBF.get(db, 1)
      assert {:halted, :stopped} = next_continuation.({:halt, :stopped})
    end
  end
end
