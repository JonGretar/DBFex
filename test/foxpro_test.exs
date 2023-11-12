defmodule FoxproTest do
  use ExUnit.Case
  doctest DBF

  describe "When reading version (31) Visual FoxPro with AutoIncrement field" do
    setup do
      db = DBF.open!("test/dbf_files/dbase_31.dbf")
      on_exit(fn -> DBF.close(db) end)
      {:ok, db: db}
    end

    test "it reads the version", context do
      assert context.db.version == 0x31
    end

    test "it reads the last updated date", context do
      assert context.db.last_updated == ~D[1902-08-02]
    end

    test "it reads the number of records", context do
      assert context.db.number_of_records == 77
    end

    test "it gets the first record", context do
      assert DBF.get(context.db, 0)
    end

    test "then the number of records should match the header", context do
      assert context.db.number_of_records == context.db |> Enum.to_list() |> length()
    end
  end


  describe "When reading version (32) Visual FoxPro with field type Varchar or Varbinary" do
    setup do
      db = DBF.open!("test/dbf_files/dbase_32.dbf")
      on_exit(fn -> DBF.close(db) end)
      {:ok, db: db}
    end

    test "it reads the version", context do
      assert context.db.version == 0x32
    end

    test "it reads the last updated date", context do
      assert context.db.last_updated == ~D[1912-01-29]
    end

    test "it reads the number of records", context do
      assert context.db.number_of_records == 1
    end

    test "it gets the first record", context do
      assert DBF.get(context.db, 0)
    end

    test "then the number of records should match the header", context do
      assert context.db.number_of_records == context.db |> Enum.to_list() |> length()
    end
  end


  describe "When reading version (f5) FoxPro with memo file" do
    setup do
      db = DBF.open!("test/dbf_files/dbase_f5.dbf")
      on_exit(fn -> DBF.close(db) end)
      {:ok, db: db}
    end

    test "it reads the version", context do
      assert context.db.version == 0xf5
    end

    test "it reads the last updated date", context do
      assert context.db.last_updated == ~D[1904-02-28]
    end

    test "it reads the number of records", context do
      assert context.db.number_of_records == 975
    end

    test "it gets the first record", context do
      assert DBF.get(context.db, 0)
    end

    test "then the number of records should match the header", context do
      assert context.db.number_of_records == context.db |> Enum.to_list() |> length()
    end
  end

end
