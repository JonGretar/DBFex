defmodule DBF.ValueDecodingTest do
  use ExUnit.Case, async: true

  alias DBF.TestFixture

  test "character fields preserve compatible blank and trimming semantics" do
    with_value_table("C", 5, ["     ", "  abc"], fn db ->
      assert {:record, %{"VALUE" => ""}} = DBF.get(db, 0)
      assert {:record, %{"VALUE" => "abc"}} = DBF.get(db, 1)
    end)
  end

  test "numeric fields preserve floats while rejecting partial values" do
    with_value_table("N", 5, ["     ", "   42", " 1.25", " 12xx"], fn db ->
      assert {:record, %{"VALUE" => nil}} = DBF.get(db, 0)
      assert {:record, %{"VALUE" => 42.0}} = DBF.get(db, 1)
      assert {:record, %{"VALUE" => 1.25}} = DBF.get(db, 2)
      assert {:record, %{"VALUE" => nil}} = DBF.get(db, 3)
    end)
  end

  test "exact numeric fields return integers or decimals according to scale" do
    with_value_table("N", 5, ["   42", "  -12"], [open_options: [numeric: :exact]], fn db ->
      assert {:record, %{"VALUE" => 42}} = DBF.get(db, 0)
      assert {:record, %{"VALUE" => -12}} = DBF.get(db, 1)
    end)

    with_value_table(
      "N",
      5,
      [" 1.25", "-0.10"],
      [decimal: 2, open_options: [numeric: :exact]],
      fn db ->
        assert {:record, %{"VALUE" => value}} = DBF.get(db, 0)
        assert Decimal.equal?(value, Decimal.new("1.25"))

        assert {:record, %{"VALUE" => value}} = DBF.get(db, 1)
        assert Decimal.equal?(value, Decimal.new("-0.10"))
      end
    )
  end

  test "float fields distinguish blank, valid, and invalid values" do
    with_value_table("F", 5, ["     ", "  2.5", " 2x  "], fn db ->
      assert {:record, %{"VALUE" => nil}} = DBF.get(db, 0)
      assert {:record, %{"VALUE" => 2.5}} = DBF.get(db, 1)

      assert {:error,
              %DBF.DatabaseError{
                reason: :invalid_record,
                context: %{record_number: 2, field_name: "VALUE", field_type: "F"}
              }} = DBF.get(db, 2)
    end)
  end

  test "logical fields distinguish blank, true, false, and invalid values" do
    with_value_table("L", 1, [" ", "?", "T", "f", "X"], fn db ->
      assert {:record, %{"VALUE" => nil}} = DBF.get(db, 0)
      assert {:record, %{"VALUE" => nil}} = DBF.get(db, 1)
      assert {:record, %{"VALUE" => true}} = DBF.get(db, 2)
      assert {:record, %{"VALUE" => false}} = DBF.get(db, 3)

      assert {:error,
              %DBF.DatabaseError{
                reason: :invalid_record,
                context: %{record_number: 4, field_name: "VALUE", field_type: "L"}
              }} = DBF.get(db, 4)
    end)
  end

  test "date fields distinguish blank, valid, and invalid values" do
    with_value_table("D", 8, ["        ", "20240229", "20240230"], fn db ->
      assert {:record, %{"VALUE" => nil}} = DBF.get(db, 0)
      assert {:record, %{"VALUE" => ~D[2024-02-29]}} = DBF.get(db, 1)

      assert {:error,
              %DBF.DatabaseError{
                reason: :invalid_record,
                context: %{record_number: 2, field_name: "VALUE", field_type: "D"}
              }} = DBF.get(db, 2)
    end)
  end

  defp with_value_table(field_type, field_length, values, options \\ [], fun) do
    records = Enum.map_join(values, &(" " <> &1))

    path =
      TestFixture.legacy_dbf(
        field_type: field_type,
        field_length: field_length,
        decimal: Keyword.get(options, :decimal, 0),
        record_count: length(values),
        records: records
      )
      |> TestFixture.write_temp!("values.dbf")

    db = DBF.open!(path, Keyword.get(options, :open_options, []))

    try do
      fun.(db)
    after
      DBF.close(db)
      TestFixture.cleanup(path)
    end
  end
end
