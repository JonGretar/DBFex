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

    test "preserves General/OLE object blocks referenced by decimal pointers" do
      DBF.with_open("test/dbf_files/foxpro2_general.dbf", fn db ->
        assert db.version == 0xF5
        assert db.memo_file.block_size == 64

        assert {:record, %{"GRAPH_ROW" => row, "GRAPH_COL" => column}} = DBF.get(db, 0)

        assert byte_size(row) == 19_355

        assert :crypto.hash(:sha256, row) ==
                 Base.decode16!(
                   "DF12298A75B657F79644391E4AFF352FA712086BBC878CB8BE7161128AD406C3"
                 )

        assert byte_size(column) == 20_081

        assert :crypto.hash(:sha256, column) ==
                 Base.decode16!(
                   "55E1A4547F4166472957916EA5864636D0382FAF731C97BF833B454D15D9F804"
                 )
      end)
    end
  end
end
