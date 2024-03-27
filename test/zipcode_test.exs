defmodule ZipcodeTest do
  use ExUnit.Case
  doctest DBF

  describe "When reading the bay area zip codes file" do
    setup do
      db = DBF.open!("test/dbf_files/bayarea_zipcodes.dbf")
      on_exit(fn -> DBF.close(db) end)
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

    test "the first record is all that we wanted", context do
      record = %{
        "Area__" => 12313263537.0,
        "Length__" => 995176.225313,
        "PO_NAME" => "NAPA",
        "STATE" => "CA",
        "ZIP" => "94558"
      }
      assert {:record, record} == DBF.get(context.db, 0)
    end

    test "it errors when requesting too high of a record ID", context do
      assert {:error, :record_not_found} == DBF.get(context.db, 187)
    end

    test "then the number of records should match the header", context do
      assert context.db.number_of_records == context.db |> Enum.to_list() |> length()
    end
  end

end
