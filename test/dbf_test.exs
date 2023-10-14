defmodule DBFTest do
  use ExUnit.Case
  doctest DBF

  describe "When reading the bay area zip codes file" do
    setup do
      db = DBF.open!("test/dbf_files/bayarea_zipcodes.dbf")
      on_exit(fn -> DBF.close!(db) end)
      {:ok, db: db}
    end

    test "it reads the version", context do
      assert context.db.version == 3
    end

    test "it reads the last updated date", context do
      assert context.db.last_updated == ~D[2009-06-16]
    end

    test "it reads the number of records", context do
      assert context.db.number_of_records == 187
    end

    test "it gets the first record", context do
      assert DBF.get(context.db, 0)
    end

    test "then the number of records should match the header", context do
      assert context.db.number_of_records == context.db |> Enum.to_list() |> length()
    end
  end

  describe "When reading version (03) dBase III without memo file" do
    setup do
      db = DBF.open!("test/dbf_files/dbase_03.dbf")
      on_exit(fn -> DBF.close!(db) end)
      {:ok, db: db}
    end

    test "it reads the version", context do
      assert context.db.version == 3
    end

    test "it reads the last updated date", context do
      assert context.db.last_updated == ~D[1905-07-13]
    end

    test "it reads the number of records", context do
      assert context.db.number_of_records == 14
    end

    test "it gets the first record", context do
      assert DBF.get(context.db, 0)
    end

    test "then the number of records should match the header", context do
      assert context.db.number_of_records == context.db |> Enum.to_list() |> length()
    end

  end

  describe "When reading version (8b) dBase IV with memo file" do
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

    test "then the number of records should match the header", context do
      assert context.db.number_of_records == context.db |> Enum.to_list() |> length()
    end

  end

  describe "When reading version (30) Visual FoxPro" do
    setup do
      db = DBF.open!("test/dbf_files/dbase_30.dbf")
      on_exit(fn -> DBF.close!(db) end)
      {:ok, db: db}
    end

    test "it reads the version", context do
      assert context.db.version == 48
    end

    test "it reads the last updated date", context do
      assert context.db.last_updated == ~D[1906-09-09]
    end

    test "it reads the number of records", context do
      assert context.db.number_of_records == 34
    end

    test "it gets the first record", context do
      assert DBF.get(context.db, 0)
    end

    test "then the number of records should match the header", context do
      assert context.db.number_of_records == context.db |> Enum.to_list() |> length()
    end

  end

end
