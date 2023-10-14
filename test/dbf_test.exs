defmodule DBFTest do
  use ExUnit.Case
  doctest DBF

  test "reads records" do
    db = DBF.open!("test/dbf_files/bayarea_zipcodes.dbf")
    DBF.read_records(db)
    assert db.number_of_records == 187
    DBF.close!(db)
  end

  describe "Reading version (03) dBase III without memo file" do
    setup do
      db = DBF.open!("test/dbf_files/dbase_03.dbf")
      on_exit(fn -> DBF.close!(db) end)
      {:ok, db: db}
    end

    test "reads the version", context do
      assert context.db.version == 3
    end

    test "reads the last updated date", context do
      assert context.db.last_updated == ~D[1905-07-13]
    end

    test "reads the number of records", context do
      assert context.db.number_of_records == 14
    end

    test "Gets the first record", context do
      assert DBF.get(context.db, 0)
    end
  end

  describe "Reading version (8b) dBase IV with memo file" do
    setup do
      db = DBF.open!("test/dbf_files/dbase_8b.dbf")
      on_exit(fn -> DBF.close!(db) end)
      {:ok, db: db}
    end

    test "reads the version", context do
      assert context.db.version == 139
    end

    test "reads the last updated date", context do
      assert context.db.last_updated == ~D[2000-06-12]
    end

    test "reads the number of records", context do
      assert context.db.number_of_records == 10
    end

    test "Gets the first record", context do
      assert DBF.get(context.db, 0)
    end
  end

  describe "Reading version (30) Visual FoxPro" do
    setup do
      db = DBF.open!("test/dbf_files/dbase_30.dbf")
      on_exit(fn -> DBF.close!(db) end)
      {:ok, db: db}
    end

    test "reads the version", context do
      assert context.db.version == 48
    end

    test "reads the last updated date", context do
      assert context.db.last_updated == ~D[1906-09-09]
    end

    test "reads the number of records", context do
      assert context.db.number_of_records == 34
    end

    test "Gets the first record", context do
      assert DBF.get(context.db, 0)
    end
  end

end
