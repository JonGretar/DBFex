defmodule DBF.ValueDecodingTest do
  use ExUnit.Case, async: true

  alias DBF.TestFixture

  test "character fields preserve compatible blank and trimming semantics" do
    with_value_table("C", 5, ["     ", "  abc"], fn db ->
      assert {:record, %{"VALUE" => ""}} = DBF.get(db, 0)
      assert {:record, %{"VALUE" => "abc"}} = DBF.get(db, 1)
    end)
  end

  defp with_value_table(field_type, field_length, values, fun) do
    records = Enum.map_join(values, &(" " <> &1))

    path =
      TestFixture.legacy_dbf(
        field_type: field_type,
        field_length: field_length,
        record_count: length(values),
        records: records
      )
      |> TestFixture.write_temp!("values.dbf")

    db = DBF.open!(path)

    try do
      fun.(db)
    after
      DBF.close(db)
      TestFixture.cleanup(path)
    end
  end
end
