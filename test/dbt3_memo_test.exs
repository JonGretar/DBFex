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

  test "decodes textual memo bytes with the caller encoding" do
    text = <<0xCF, 0xF0, 0xE8, 0xE2, 0xE5, 0xF2>>
    memo = dbt3_header(2) <> text <> <<0x1A, 0x1A>> <> :binary.copy(<<0>>, 504)

    with_dbt3(memo, 1, [encoding: :windows_1251], fn db ->
      assert {:record, %{"VALUE" => "Привет"}} = DBF.get(db, 0)
    end)
  end

  test "rejects malformed textual memo pointers" do
    memo = dbt3_header(1)

    error =
      assert_raise DBF.DatabaseError, fn ->
        with_dbt3(memo, "not-a-ptr", fn _db -> :ok end)
      end

    assert error.reason == :invalid_memo
    assert error.cause == :invalid_memo_pointer
    assert error.context.field_name == "VALUE"
    assert error.context.raw_pointer == "not-a-ptr"
  end

  test "rejects out-of-range memo pointers" do
    memo = dbt3_header(1)

    error =
      assert_raise DBF.DatabaseError, fn ->
        with_dbt3(memo, 9, fn _db -> :ok end)
      end

    assert error.reason == :invalid_memo
    assert error.cause == :invalid_memo_pointer
    assert error.context.memo_block == 9
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

  defp with_dbt3(memo, pointer, open_options \\ [], fun) do
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
      db = DBF.open!(path, open_options)

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
