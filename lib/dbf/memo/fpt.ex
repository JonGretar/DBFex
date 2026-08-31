defmodule DBF.Memo.FPT do
  @moduledoc false

  alias DBF.Error
  alias DBF.Memo
  alias DBF.Resource

  @header_bytes 512
  @block_header_bytes 8
  @text_block_type 1

  @spec initialize(Resource.t(), non_neg_integer() | nil) ::
          {:ok, Memo.t()} | {:error, Error.t()}
  def initialize(resource, probe_block) do
    with {:ok,
          <<next_block::big-unsigned-integer-size(32), _reserved::binary-size(2),
            block_size::big-unsigned-integer-size(16),
            _rest::binary>>} <-
           Resource.read_exact(resource, :memo, 0, @header_bytes),
         {:ok, size} <- Resource.size(resource, :memo),
         :ok <- validate_header(next_block, block_size, size),
         :ok <- verify_probe(resource, probe_block, block_size, size) do
      {:ok, %Memo{family: :fpt, block_size: block_size}}
    else
      {:error, %Error{} = error} -> {:error, %Error{error | reason: :invalid_memo}}
      {:error, cause, context} -> {:error, memo_error(cause, context)}
    end
  end

  @spec get_block(Resource.t(), Memo.t(), non_neg_integer()) ::
          binary() | {:error, Error.t()}
  def get_block(resource, %Memo{block_size: block_size}, block_number) do
    with {:ok, size} <- Resource.size(resource, :memo),
         {:ok, offset} <- validate_pointer(block_number, block_size, size),
         {:ok, header} <-
           Resource.read_exact(resource, :memo, offset, @block_header_bytes),
         {:ok, payload_length} <- parse_block_header(header, block_number, offset),
         :ok <- validate_payload_bounds(offset, payload_length, size, block_number),
         {:ok, payload} <-
           Resource.read_exact(
             resource,
             :memo,
             offset + @block_header_bytes,
             payload_length
           ) do
      payload
    else
      {:error, %Error{} = error} -> {:error, %Error{error | reason: :invalid_memo}}
      {:error, cause, context} -> {:error, memo_error(cause, context)}
    end
  end

  # Microsoft Visual FoxPro FPT structure:
  # https://learn.microsoft.com/en-us/previous-versions/visualstudio/foxpro/8599s21w(v=vs.71)
  defp parse_block_header(
         <<@text_block_type::big-unsigned-integer-size(32),
           payload_length::big-unsigned-integer-size(32)>>,
         _block_number,
         _offset
       ) do
    {:ok, payload_length}
  end

  defp parse_block_header(
         <<block_type::big-unsigned-integer-size(32), _payload_length::binary>>,
         block_number,
         offset
       ) do
    {:error, :unsupported_memo_block_type,
     %{memo_block: block_number, block_type: block_type, offset: offset}}
  end

  defp validate_payload_bounds(offset, payload_length, size, block_number) do
    if offset + @block_header_bytes + payload_length <= size do
      :ok
    else
      {:error, :truncated_memo_block,
       %{
         memo_block: block_number,
         declared_bytes: payload_length,
         available_bytes: max(size - offset - @block_header_bytes, 0),
         offset: offset
       }}
    end
  end

  defp validate_pointer(block_number, block_size, size)
       when is_integer(block_number) and block_number >= 1 do
    offset = block_number * block_size

    if offset >= @header_bytes and offset + @block_header_bytes <= size do
      {:ok, offset}
    else
      {:error, :invalid_memo_pointer, %{memo_block: block_number, memo_bytes: size}}
    end
  end

  defp validate_pointer(block_number, _block_size, size) do
    {:error, :invalid_memo_pointer, %{memo_block: block_number, memo_bytes: size}}
  end

  defp verify_probe(_resource, nil, _block_size, _size), do: :ok

  defp verify_probe(resource, probe_block, block_size, size) do
    with {:ok, offset} <- validate_pointer(probe_block, block_size, size),
         {:ok, header} <-
           Resource.read_exact(resource, :memo, offset, @block_header_bytes),
         {:ok, payload_length} <- parse_block_header(header, probe_block, offset) do
      validate_payload_bounds(offset, payload_length, size, probe_block)
    end
  end

  defp validate_header(next_block, block_size, size)
       when block_size >= 1 and next_block >= 1 do
    first_data_block = div(@header_bytes + block_size - 1, block_size)

    if next_block >= first_data_block and size > (next_block - 1) * block_size and
         size <= next_block * block_size do
      :ok
    else
      invalid_header(next_block, block_size, size)
    end
  end

  defp validate_header(next_block, block_size, size) do
    invalid_header(next_block, block_size, size)
  end

  defp invalid_header(next_block, block_size, size) do
    {:error, :invalid_memo_header,
     %{
       next_block: next_block,
       block_size: block_size,
       actual_bytes: size,
       offset: 0
     }}
  end

  defp memo_error(cause, context), do: Error.new(:invalid_memo, cause, context)
end
