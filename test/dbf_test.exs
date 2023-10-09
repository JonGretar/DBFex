defmodule DBFTest do
  use ExUnit.Case
  doctest DBF

  test "greets the world" do
    assert DBF.hello() == :world
  end

  test "opens" do
    assert DBF.open!("test/dbf_files/bayarea_zipcodes.dbf") == :world
  end

end
