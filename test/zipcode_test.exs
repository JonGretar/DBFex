defmodule ZipcodeTest do
  use ExUnit.Case
  doctest DBF

  @csv_oracle "test/dbf_files/bayarea_zipcodes.csv"

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

    test "all records match the independently generated CSV oracle", context do
      expected =
        @csv_oracle
        |> File.stream!()
        |> Stream.drop(1)
        |> Enum.map(&parse_csv_record/1)

      assert expected ==
               Enum.map(context.db, fn
                 {:record, record} -> record
               end)
    end

    test "the complete schema matches the CSV and descriptor metadata", context do
      assert [
               {"ZIP", "C", 5, 0},
               {"PO_NAME", "C", 28, 0},
               {"STATE", "C", 2, 0},
               {"Area__", "F", 19, 11},
               {"Length__", "F", 19, 11}
             ] ==
               Enum.map(context.db.fields, &{&1.name, &1.type, &1.length, &1.decimal})
    end

    test "it errors when requesting too high of a record ID", context do
      assert {:error, %DBF.DatabaseError{reason: :invalid_record_index}} =
               DBF.get(context.db, 187)
    end

    test "then the number of records should match the header", context do
      assert context.db.number_of_records == context.db |> Enum.to_list() |> length()
    end
  end

  defp parse_csv_record(line) do
    [zip, po_name, state, area, length] =
      line
      |> String.trim_trailing()
      |> String.split(";")

    %{
      "ZIP" => zip,
      "PO_NAME" => po_name,
      "STATE" => state,
      "Area__" => parse_float!(area),
      "Length__" => parse_float!(length)
    }
  end

  defp parse_float!(value) do
    case Float.parse(value) do
      {number, ""} -> number
    end
  end
end
