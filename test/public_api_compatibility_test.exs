defmodule DBF.PublicAPICompatibilityTest do
  use ExUnit.Case

  alias DBF.Resource
  alias DBF.TestFixture

  @zipcodes "test/dbf_files/bayarea_zipcodes.dbf"
  @dbase3_memo "test/dbf_files/dbase_83.dbf"
  @dbase3_memo_file "test/dbf_files/dbase_83.dbt"

  describe "opening and closing" do
    test "open/1 and open/2 return an open database" do
      assert {:ok, db1} = DBF.open(@zipcodes)
      assert :ok = DBF.close(db1)
      assert :ok = DBF.close(db1)

      assert {:ok, db2} = DBF.open(@zipcodes, [])
      assert :ok = DBF.close(db2)
    end

    test "using a database after close returns a public resource error" do
      assert {:ok, db} = DBF.open(@zipcodes)
      assert :ok = DBF.close(db)

      assert {:error, %DBF.DatabaseError{reason: :file_error}} = DBF.get(db, 0)
    end

    test "open!/1 and open!/2 return an open database" do
      db1 = DBF.open!(@zipcodes)
      assert :ok = DBF.close(db1)

      db2 = DBF.open!(@zipcodes, [])
      assert :ok = DBF.close(db2)
    end

    test "with_open/2 returns the callback result and closes the database" do
      resource = DBF.with_open(@zipcodes, & &1.resource)

      refute Resource.open?(resource)
    end

    test "with_open/3 closes the table and memo resource" do
      resource =
        DBF.with_open(@dbase3_memo, [memo_file: @dbase3_memo_file], & &1.resource)

      refute Resource.open?(resource)
    end

    test "with_open does not invoke the callback when opening fails" do
      assert {:error, %DBF.DatabaseError{reason: :unsupported_version}} =
               DBF.with_open("test/dbf_files/cp1251.dbf", fn _db ->
                 flunk("the callback must not run")
               end)
    end

    test "with_open closes the database before propagating a callback exception" do
      parent = self()

      assert_raise RuntimeError, "callback failed", fn ->
        DBF.with_open(@zipcodes, fn db ->
          send(parent, {:resource, db.resource})
          raise "callback failed"
        end)
      end

      assert_receive {:resource, resource}
      refute Resource.open?(resource)
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
                context: %{version: 0x30}
              }} = DBF.open("test/dbf_files/cp1251.dbf")

      assert_raise DBF.DatabaseError, fn ->
        DBF.open!("test/dbf_files/cp1251.dbf")
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

    test "invalid record indexes use one database error category", %{db: db} do
      for index <- [-1, 0.5, "0", 187, 999] do
        assert {:error,
                %DBF.DatabaseError{
                  reason: :invalid_record_index,
                  context: %{record_number: ^index, record_count: 187}
                }} = DBF.get(db, index)
      end
    end

    test "a record truncated after opening returns an invalid-record error" do
      binary = TestFixture.legacy_dbf(record_count: 1, records: " A")
      path = TestFixture.write_temp!(binary)
      on_exit(fn -> TestFixture.cleanup(path) end)

      truncated_db = DBF.open!(path)
      on_exit(fn -> DBF.close(truncated_db) end)
      File.write!(path, binary_part(binary, 0, byte_size(binary) - 1))

      assert {:error,
              %DBF.DatabaseError{
                reason: :invalid_record,
                cause: :eof,
                context: %{record_number: 0, actual: 1, expected: 2}
              }} = DBF.get(truncated_db, 0)
    end

    test "malformed field values return contextual invalid-record errors" do
      path =
        TestFixture.legacy_dbf(field_type: "L", record_count: 1, records: " X")
        |> TestFixture.write_temp!()

      on_exit(fn -> TestFixture.cleanup(path) end)
      invalid_db = DBF.open!(path)
      on_exit(fn -> DBF.close(invalid_db) end)

      assert {:error,
              %DBF.DatabaseError{
                reason: :invalid_record,
                cause: {:field_decode_failed, _message},
                context: %{record_number: 0, field_name: "VALUE", field_type: "L"}
              }} = DBF.get(invalid_db, 0)
    end

    test "unknown record markers return an invalid-record error" do
      path = TestFixture.with_record_marker!(@zipcodes, 0, "?")
      on_exit(fn -> TestFixture.cleanup(path) end)

      invalid_db = DBF.open!(path)
      on_exit(fn -> DBF.close(invalid_db) end)

      assert {:error,
              %DBF.DatabaseError{
                reason: :invalid_record,
                cause: {:unknown_record_marker, ??},
                context: %{record_number: 0}
              }} = DBF.get(invalid_db, 0)
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

    test "a record error is emitted once as the final element" do
      path = TestFixture.with_record_marker!(@zipcodes, 1, "?")
      on_exit(fn -> TestFixture.cleanup(path) end)

      invalid_db = DBF.open!(path)
      on_exit(fn -> DBF.close(invalid_db) end)

      assert [first, {:error, %DBF.DatabaseError{reason: :invalid_record}}] =
               Enum.to_list(invalid_db)

      assert first == DBF.get(invalid_db, 0)
    end

    test "suspending on a record error resumes directly to completion" do
      path = TestFixture.with_record_marker!(@zipcodes, 0, "?")
      on_exit(fn -> TestFixture.cleanup(path) end)

      invalid_db = DBF.open!(path)
      on_exit(fn -> DBF.close(invalid_db) end)
      reducer = fn record, records -> {:suspend, [record | records]} end

      assert {:suspended, [{:error, %DBF.DatabaseError{reason: :invalid_record}}], continuation} =
               Enumerable.reduce(invalid_db, {:cont, []}, reducer)

      assert {:done, []} = continuation.({:cont, []})
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
