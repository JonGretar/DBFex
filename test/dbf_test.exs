defmodule DBFTest do
  use ExUnit.Case
  doctest DBF

  test "greets the world" do
    assert DBF.hello() == :world
  end

  test "opens" do
    assert {:ok, %DBF.Database{}} == DBF.open("test/dbf_files/bayarea_zipcodes.dbf")
  end

  test "reads records" do
    db = DBF.open!("test/dbf_files/bayarea_zipcodes.dbf")
    DBF.read_records(db)
    assert db.number_of_records == 187
    DBF.close!(db)
  end

end
