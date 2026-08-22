defmodule DBF.Memo.DBT3Test do
  use ExUnit.Case

  alias DBF.TestFixture

  test "reads memo text across blocks when the terminator crosses a block boundary" do
    text = :binary.copy("a", 511)
    memo = dbt3_header(3) <> text <> <<0x1A>> <> <<0x1A>> <> :binary.copy(<<0>>, 510)

    with_dbt3(memo, 1, fn db ->
      assert {:record, %{"VALUE" => ^text}} = DBF.get(db, 0)
    end)
  end

  test "rejects memo data without a terminator" do
    memo = dbt3_header(2) <> :binary.copy("a", 512)

    with_dbt3(memo, 1, fn db ->
      assert {:error,
              %DBF.DatabaseError{
                reason: :invalid_memo,
                cause: :missing_memo_terminator,
                context: %{memo_block: 1}
              }} = DBF.get(db, 0)
    end)
  end

  test "rejects malformed textual memo pointers" do
    memo = dbt3_header(1)

    with_dbt3(memo, "not-a-ptr", fn db ->
      assert {:error,
              %DBF.DatabaseError{
                reason: :invalid_memo,
                cause: :invalid_memo_pointer,
                context: %{field_name: "VALUE", raw_pointer: "not-a-ptr"}
              }} = DBF.get(db, 0)
    end)
  end

  test "rejects out-of-range memo pointers" do
    memo = dbt3_header(1)

    with_dbt3(memo, 9, fn db ->
      assert {:error,
              %DBF.DatabaseError{
                reason: :invalid_memo,
                cause: :invalid_memo_pointer,
                context: %{memo_block: 9}
              }} = DBF.get(db, 0)
    end)
  end

  test "rejects a next-block declaration inconsistent with the file size" do
    memo = dbt3_header(3)

    error =
      assert_raise DBF.DatabaseError, fn ->
        with_dbt3(memo, 1, fn _db -> :ok end)
      end

    assert error.reason == :invalid_memo
    assert error.cause == :invalid_memo_header
  end

  defp with_dbt3(memo, pointer, fun) do
    pointer = if is_integer(pointer), do: Integer.to_string(pointer), else: pointer
    record = " " <> String.pad_leading(pointer, 10)

    path =
      TestFixture.legacy_dbf(
        version: 0x83,
        field_type: "M",
        field_length: 10,
        record_count: 1,
        records: record
      )
      |> TestFixture.write_temp!("memo.dbf")

    File.write!(Path.rootname(path) <> ".dbt", memo)

    try do
      db = DBF.open!(path)

      try do
        fun.(db)
      after
        DBF.close(db)
      end
    after
      TestFixture.cleanup(path)
    end
  end

  defp dbt3_header(next_block) do
    <<next_block::little-unsigned-integer-size(32)>> <> :binary.copy(<<0>>, 508)
  end
end
