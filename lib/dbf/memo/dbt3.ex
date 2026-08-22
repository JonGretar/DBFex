defmodule DBF.Memo.DBT3 do
  @moduledoc false

  alias DBF.Error
  alias DBF.Memo
  alias DBF.Resource

  @block_size 512
  @terminator <<0x1A, 0x1A>>

  @spec initialize(Resource.t()) :: {:ok, Memo.t()} | {:error, Error.t()}
  def initialize(resource) do
    with {:ok, <<next_block::little-unsigned-integer-size(32), _rest::binary>>} <-
           Resource.read_exact(resource, :memo, 0, @block_size),
         {:ok, size} <- Resource.size(resource, :memo),
         :ok <- validate_header(next_block, size) do
      {:ok, %Memo{family: :dbt_iii, block_size: @block_size}}
    else
      {:error, %Error{} = error} -> {:error, %Error{error | reason: :invalid_memo}}
      {:error, cause, context} -> {:error, memo_error(cause, context)}
    end
  end

  @spec get_block(Resource.t(), Memo.t(), non_neg_integer()) ::
          binary() | {:error, Error.t()}
  def get_block(resource, %Memo{}, block_number) do
    with {:ok, size} <- Resource.size(resource, :memo),
         {:ok, offset} <- validate_pointer(block_number, size) do
      read_until_terminator(resource, offset, size, block_number, [], <<>>)
    else
      {:error, %Error{} = error} -> {:error, %Error{error | reason: :invalid_memo}}
      {:error, cause, context} -> {:error, memo_error(cause, context)}
    end
  end

  defp read_until_terminator(_resource, offset, size, block_number, _chunks, _carry)
       when offset >= size do
    {:error,
     memo_error(:missing_memo_terminator, %{
       memo_block: block_number,
       offset: offset
     })}
  end

  defp read_until_terminator(resource, offset, size, block_number, chunks, carry) do
    length = min(@block_size, size - offset)

    case Resource.read_exact(resource, :memo, offset, length) do
      {:ok, data} ->
        scan_chunk(resource, offset, size, block_number, chunks, carry <> data)

      {:error, %Error{} = error} ->
        {:error, %Error{error | reason: :invalid_memo}}
    end
  end

  defp scan_chunk(resource, offset, size, block_number, chunks, data) do
    case :binary.match(data, @terminator) do
      {terminator_offset, 2} ->
        final_chunk = binary_part(data, 0, terminator_offset)
        chunks |> then(&[final_chunk | &1]) |> Enum.reverse() |> IO.iodata_to_binary()

      :nomatch ->
        {chunk, carry} = retain_possible_terminator(data)

        read_until_terminator(
          resource,
          offset + min(@block_size, size - offset),
          size,
          block_number,
          [chunk | chunks],
          carry
        )
    end
  end

  defp retain_possible_terminator(<<>>), do: {<<>>, <<>>}

  defp retain_possible_terminator(data) do
    if :binary.last(data) == 0x1A do
      {binary_part(data, 0, byte_size(data) - 1), <<0x1A>>}
    else
      {data, <<>>}
    end
  end

  defp validate_header(next_block, size)
       when next_block >= 1 and size > (next_block - 1) * @block_size and
              size <= next_block * @block_size,
       do: :ok

  defp validate_header(next_block, size) do
    {:error, :invalid_memo_header, %{next_block: next_block, actual_bytes: size, offset: 0}}
  end

  defp validate_pointer(block_number, size)
       when is_integer(block_number) and block_number >= 1 and block_number * @block_size < size do
    {:ok, block_number * @block_size}
  end

  defp validate_pointer(block_number, size) do
    {:error, :invalid_memo_pointer, %{memo_block: block_number, memo_bytes: size}}
  end

  defp memo_error(cause, context), do: Error.new(:invalid_memo, cause, context)
end
