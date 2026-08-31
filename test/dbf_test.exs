defmodule DBFTest do
  use ExUnit.Case
  doctest DBF

  describe "when reading version (0xf5) FoxPro with memo file" do
    test "reads the complete fixture and representative text memo" do
      DBF.with_open("test/dbf_files/dbase_f5.dbf", fn db ->
        assert db.version == 0xF5
        assert db.number_of_records == 975
        assert length(db.fields) == 59

        assert {:record, %{"NF" => 2.0, "OBSE" => memo}} = DBF.get(db, 1)
        assert byte_size(memo) == 2752
        assert String.starts_with?(memo, "El meu pare.\r\nGuerra: \r\n")
        assert Enum.count(db) == 975
      end)
    end
  end
end
