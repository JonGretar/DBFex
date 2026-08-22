defmodule DBFTest do
  use ExUnit.Case
  doctest DBF

  describe "When reading version (0xf5) FoxPro with memo file" do
    test "it errors on unsupported version" do
      assert {:error,
              %DBF.DatabaseError{
                reason: :unsupported_version,
                context: %{version: 0xF5}
              }} = DBF.open("test/dbf_files/dbase_f5.dbf")
    end
  end
end
