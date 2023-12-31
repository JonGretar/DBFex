defmodule DBFTest do
  use ExUnit.Case
  doctest DBF


  describe "When reading version (02) FoxBase" do
    setup do
      db = DBF.open!("test/dbf_files/dbase_02.dbf")
      on_exit(fn -> DBF.close(db) end)
      {:ok, db: db}
    end

    test "it reads the version", context do
      assert context.db.version == 0x02
    end

    test "it reads the last updated date", context do
      assert context.db.last_updated == ~D[1900-01-01]
    end

    test "it reads the number of records", context do
      assert context.db.number_of_records == 9
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
      on_exit(fn -> DBF.close(db) end)
      {:ok, db: db}
    end

    test "it reads the version", context do
      assert context.db.version == 0x03
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
      on_exit(fn -> DBF.close(db) end)
      {:ok, db: db}
    end

    test "reads the version", context do
      assert context.db.version == 0x8b
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

  describe "When reading version (83) dBase III with memo file" do
    setup do
      db = DBF.open!("test/dbf_files/dbase_83.dbf")
      on_exit(fn -> DBF.close(db) end)
      {:ok, db: db}
    end

    test "it reads the version", context do
      assert context.db.version == 0x83
    end

    test "it reads the last updated date", context do
      assert context.db.last_updated == ~D[2003-12-18]
    end

    test "it reads the number of records", context do
      assert context.db.number_of_records == 67
    end

    test "it gets the first record", context do
      assert DBF.get(context.db, 0)
    end

    test "then the number of records should match the header", context do
      assert context.db.number_of_records == context.db |> Enum.to_list() |> length()
    end
  end


end
