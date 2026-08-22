defmodule DBF.Memo.DBT4Test do
  use ExUnit.Case

  alias DBF.TestFixture

  test "reads the fixture's declared memo payloads and blank pointer" do
    db = DBF.open!("test/dbf_files/dbase_8b.dbf")
    on_exit(fn -> DBF.close(db) end)

    assert [
             "First memo",
             "Second memo",
             "Thierd memo",
             "Fourth memo",
             "Fifth memo",
             "Sixth memo",
             "Seventh memo",
             "Eigth memo",
             "Nineth memo",
             nil
           ] == Enum.map(db, fn {:record, record} -> record["MEMO"] end)
  end

  test "uses the block size declared at header offset 20" do
    memo = dbt4_file("large blocks", block_size: 1024)

    with_dbt4(memo, 1, fn db ->
      assert {:record, %{"VALUE" => "large blocks"}} = DBF.get(db, 0)
    end)
  end

  test "validates the referenced block instead of assuming block one is used" do
    block_size = 512
    text = "later block"

    block =
      <<0xFF, 0xFF, 0x08, 0x00, byte_size(text) + 8::little-unsigned-integer-size(32)>> <> text

    memo =
      dbt4_header(3, block_size) <>
        :binary.copy(<<0>>, block_size) <>
        block <>
        :binary.copy(<<0>>, block_size - byte_size(block))

    with_dbt4(memo, 2, fn db ->
      assert {:record, %{"VALUE" => "later block"}} = DBF.get(db, 0)
    end)
  end

  test "reads declared payloads spanning multiple blocks" do
    text = :binary.copy("memo", 300)
    memo = dbt4_file(text)

    with_dbt4(memo, 1, fn db ->
      assert {:record, %{"VALUE" => ^text}} = DBF.get(db, 0)
    end)
  end

  test "stops textual memos at the dBASE IV field terminator" do
    memo = dbt4_file("value" <> <<0x1F>> <> "padding")

    with_dbt4(memo, 1, fn db ->
      assert {:record, %{"VALUE" => "value"}} = DBF.get(db, 0)
    end)
  end

  test "rejects an invalid memo block signature" do
    memo = dbt4_file("memo", signature: <<0, 0, 0, 0>>)

    error =
      assert_raise DBF.DatabaseError, fn ->
        with_dbt4(memo, 1, fn _db -> :ok end)
      end

    assert error.reason == :invalid_memo
    assert error.cause == :invalid_memo_block_signature
  end

  test "rejects a declared payload extending beyond the memo file" do
    memo = dbt4_file("short", declared_length: 1000, pad_file: false)

    with_dbt4(memo, 1, fn db ->
      assert {:error,
              %DBF.DatabaseError{
                reason: :invalid_memo,
                cause: :truncated_memo_block,
                context: %{memo_block: 1, declared_bytes: 1000}
              }} = DBF.get(db, 0)
    end)
  end

  test "rejects out-of-range memo pointers" do
    memo = dbt4_file("memo")

    error =
      assert_raise DBF.DatabaseError, fn ->
        with_dbt4(memo, 9, fn _db -> :ok end)
      end

    assert error.reason == :invalid_memo
    assert error.cause == :invalid_memo_pointer
    assert error.context.memo_block == 9
  end

  defp with_dbt4(memo, pointer, fun) do
    record = " " <> String.pad_leading(Integer.to_string(pointer), 10)

    path =
      TestFixture.legacy_dbf(
        version: 0x8B,
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

  defp dbt4_file(text, options \\ []) do
    block_size = Keyword.get(options, :block_size, 512)
    signature = Keyword.get(options, :signature, <<0xFF, 0xFF, 0x08, 0x00>>)
    declared_length = Keyword.get(options, :declared_length, byte_size(text) + 8)
    block = signature <> <<declared_length::little-unsigned-integer-size(32)>> <> text
    used_blocks = div(byte_size(block) + block_size - 1, block_size)
    next_block = 1 + used_blocks
    header = dbt4_header(next_block, block_size)
    prefix = header <> :binary.copy(<<0>>, block_size - byte_size(header))
    memo = prefix <> block

    if Keyword.get(options, :pad_file, true) do
      memo <> :binary.copy(<<0>>, next_block * block_size - byte_size(memo))
    else
      memo
    end
  end

  defp dbt4_header(next_block, block_size) do
    <<next_block::little-unsigned-integer-size(32)>> <>
      :binary.copy(<<0>>, 16) <>
      <<block_size::little-unsigned-integer-size(16)>> <>
      :binary.copy(<<0>>, 490)
  end
end
