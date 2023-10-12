defmodule DBFTest do
  use ExUnit.Case
  doctest DBF

  test "reads records" do
    db = DBF.open!("test/dbf_files/bayarea_zipcodes.dbf")
    DBF.read_records(db)
    assert db.number_of_records == 187
    DBF.close!(db)
  end

end
