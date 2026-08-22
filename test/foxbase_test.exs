defmodule FoxBaseTest do
  use ExUnit.Case
  doctest DBF

  alias DBF.TestFixture

  @fixture "test/dbf_files/dbase_02.dbf"
  @records_oracle "test/dbf_files/dbase_02_records.exs"

  describe "When reading version (02) FoxBase" do
    setup do
      db = DBF.open!(@fixture)
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

    test "all records match the checked-in fixed-width oracle", context do
      {expected, _binding} = Code.eval_file(@records_oracle)

      assert expected ==
               Enum.map(context.db, fn
                 {:record, record} -> record
               end)
    end

    test "the complete schema matches the independent summary", context do
      actual =
        Enum.map(context.db.fields, fn field ->
          {field.name, field.type, field.length, field.decimal}
        end)

      assert actual == [
               {"EMP:NMBR", "N", 3, nil},
               {"LAST", "C", 10, nil},
               {"FIRST", "C", 10, nil},
               {"ADDR", "C", 20, nil},
               {"CITY", "C", 15, nil},
               {"ZIP:CODE", "C", 10, nil},
               {"PHONE", "C", 9, nil},
               {"SSN", "C", 11, nil},
               {"HIREDATE", "C", 8, nil},
               {"TERMDATE", "C", 8, nil},
               {"CLASS", "C", 3, nil},
               {"DEPT", "C", 3, nil},
               {"PAYRATE", "N", 8, nil},
               {"START:PAY", "N", 8, nil}
             ]
    end

    test "deleted records preserve their values and status", context do
      path = TestFixture.with_record_marker!(@fixture, 0, "*")
      on_exit(fn -> TestFixture.cleanup(path) end)

      db = DBF.open!(path)
      on_exit(fn -> DBF.close(db) end)

      assert {:record, expected} = DBF.get(context.db, 0)
      assert {:deleted_record, ^expected} = DBF.get(db, 0)
    end

    test "exact numerics preserve values when FoxBase descriptors omit scale metadata" do
      db = DBF.open!(@fixture, numeric: :exact)
      on_exit(fn -> DBF.close(db) end)

      assert {:record, first} = DBF.get(db, 0)
      assert first["EMP:NMBR"] == 2
      assert Decimal.equal?(first["PAYRATE"], Decimal.new("6.000"))

      assert {:record, fractional} = DBF.get(db, 4)
      assert Decimal.equal?(fractional["PAYRATE"], Decimal.new("3838.383"))

      assert {:record, blank} = DBF.get(db, 7)
      assert blank["START:PAY"] == nil
    end

    test "then the number of records should match the header", context do
      assert context.db.number_of_records == context.db |> Enum.to_list() |> length()
    end
  end
end
