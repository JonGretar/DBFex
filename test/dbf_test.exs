defmodule DBFTest do
  use ExUnit.Case
  doctest DBF

  describe "When reading version (0xf5) FoxPro with memo file" do
    test "it errors on unsupported version" do
      exception = DBF.DatabaseError.new(:unsupported_version, "FoxPro with memo file")
      assert {:error, exception} == DBF.open("test/dbf_files/dbase_f5.dbf")
    end
  end

end
