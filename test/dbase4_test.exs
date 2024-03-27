defmodule DBase4Test do
  use ExUnit.Case
  doctest DBF

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

    test "the first record is all that we wanted", context do
      record = %{
        "CHARACTER" => "One",
        "DATE" => ~D[1970-01-01],
        "FLOAT" => 1.23456789012346,
        "LOGICAL" => true,
        "MEMO" => "First memo",
        "NUMERICAL" => 1.0
      }
      assert {:record, record} == DBF.get(context.db, 0)
    end

    test "then the number of records should match the header", context do
      assert context.db.number_of_records == context.db |> Enum.to_list() |> length()
    end

  end

end
