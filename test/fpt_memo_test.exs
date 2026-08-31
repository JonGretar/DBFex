defmodule DBF.Memo.FPTTest do
  use ExUnit.Case

  alias DBF.TestFixture

  test "uses the big-endian block size and returns the exact declared payload" do
    text = :binary.copy("memo\r\n", 200)
    block_size = 1024
    {memo, pointer} = fpt_file(text, block_size: block_size)

    with_fpt(memo, pointer, fn db ->
      assert db.memo_file.block_size == block_size
      assert {:record, %{"VALUE" => ^text}} = DBF.get(db, 0)
    end)
  end

  test "rejects a non-text block referenced by a text memo field" do
    {memo, pointer} = fpt_file(<<0, 1, 2, 3>>, block_type: 0)

    error =
      assert_raise DBF.DatabaseError, fn ->
        with_fpt(memo, pointer, fn _db -> :ok end)
      end

    assert error.reason == :invalid_memo
    assert error.cause == :unsupported_memo_block_type
    assert error.context.memo_block == pointer
    assert error.context.block_type == 0
  end

  test "rejects a zero block size in the FPT header" do
    {<<prefix::binary-size(6), _block_size::binary-size(2), rest::binary>>, pointer} =
      fpt_file("memo")

    error =
      assert_raise DBF.DatabaseError, fn ->
        with_fpt(prefix <> <<0, 0>> <> rest, pointer, fn _db -> :ok end)
      end

    assert error.reason == :invalid_memo
    assert error.cause == :invalid_memo_header
    assert error.context.block_size == 0
  end

  test "rejects a declared payload extending beyond the memo file" do
    {memo, pointer} = fpt_file("short", declared_length: 1000, pad_file: false)

    error =
      assert_raise DBF.DatabaseError, fn ->
        with_fpt(memo, pointer, fn _db -> :ok end)
      end

    assert error.reason == :invalid_memo
    assert error.cause == :truncated_memo_block
    assert error.context.memo_block == pointer
    assert error.context.declared_bytes == 1000
  end

  test "rejects an out-of-range memo pointer" do
    {memo, _pointer} = fpt_file("memo")

    error =
      assert_raise DBF.DatabaseError, fn ->
        with_fpt(memo, 999, fn _db -> :ok end)
      end

    assert error.reason == :invalid_memo
    assert error.cause == :invalid_memo_pointer
    assert error.context.memo_block == 999
  end

  defp with_fpt(memo, pointer, fun) do
    record = " " <> String.pad_leading(Integer.to_string(pointer), 10)

    path =
      TestFixture.legacy_dbf(
        version: 0xF5,
        field_type: "M",
        field_length: 10,
        record_count: 1,
        records: record
      )
      |> TestFixture.write_temp!("memo.dbf")

    File.write!(Path.rootname(path) <> ".fpt", memo)

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

  defp fpt_file(text, options \\ []) do
    block_size = Keyword.get(options, :block_size, 64)
    block_type = Keyword.get(options, :block_type, 1)
    declared_length = Keyword.get(options, :declared_length, byte_size(text))
    first_block = div(512 + block_size - 1, block_size)

    block =
      <<block_type::big-unsigned-integer-size(32),
        declared_length::big-unsigned-integer-size(32)>> <> text

    used_blocks = div(byte_size(block) + block_size - 1, block_size)
    next_block = first_block + used_blocks

    header =
      <<next_block::big-unsigned-integer-size(32), 0::size(16),
        block_size::big-unsigned-integer-size(16)>> <> :binary.copy(<<0>>, 504)

    memo =
      header <>
        :binary.copy(<<0>>, first_block * block_size - byte_size(header)) <>
        block

    memo =
      if Keyword.get(options, :pad_file, true) do
        memo <> :binary.copy(<<0>>, next_block * block_size - byte_size(memo))
      else
        memo
      end

    {memo, first_block}
  end
end
