defmodule DBF.Memo.DBT4 do
  @moduledoc false

  alias DBF.Error
  alias DBF.Memo
  alias DBF.Resource

  @header_bytes 512
  @default_block_size 512
  @block_signature <<0xFF, 0xFF, 0x08, 0x00>>
  @text_terminators [<<0x1F>>, <<0x1A>>]

  @spec initialize(Resource.t()) :: {:ok, Memo.t()} | {:error, Error.t()}
  def initialize(resource) do
    with {:ok,
          <<next_block::little-unsigned-integer-size(32), _reserved::binary-size(16),
            declared_block_size::little-unsigned-integer-size(16),
            _rest::binary>>} <-
           Resource.read_exact(resource, :memo, 0, @header_bytes),
         block_size <- normalize_block_size(declared_block_size),
         {:ok, size} <- Resource.size(resource, :memo),
         :ok <- validate_header(next_block, block_size, size) do
      {:ok, %Memo{family: :dbt_iv, block_size: block_size}}
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
         {:ok, header} <- Resource.read_exact(resource, :memo, offset, 8),
         {:ok, declared_length} <- parse_block_header(header, block_number, offset),
         payload_length <- declared_length - 8,
         :ok <- validate_payload_bounds(offset, declared_length, size, block_number),
         {:ok, payload} <- Resource.read_exact(resource, :memo, offset + 8, payload_length) do
      clean_text(payload)
    else
      {:error, %Error{} = error} -> {:error, %Error{error | reason: :invalid_memo}}
      {:error, cause, context} -> {:error, memo_error(cause, context)}
    end
  end

  defp parse_block_header(
         <<@block_signature, declared_length::little-unsigned-integer-size(32)>>,
         _block_number,
         _offset
       )
       when declared_length >= 8 do
    {:ok, declared_length}
  end

  defp parse_block_header(
         <<@block_signature, declared_length::little-unsigned-integer-size(32)>>,
         block_number,
         offset
       ) do
    {:error, :invalid_memo_length,
     %{memo_block: block_number, declared_bytes: declared_length, offset: offset + 4}}
  end

  defp parse_block_header(<<signature::binary-size(4), _length::binary>>, block_number, offset) do
    {:error, :invalid_memo_block_signature,
     %{memo_block: block_number, signature: signature, offset: offset}}
  end

  defp validate_payload_bounds(offset, declared_length, size, block_number) do
    if offset + declared_length <= size do
      :ok
    else
      {:error, :truncated_memo_block,
       %{
         memo_block: block_number,
         declared_bytes: declared_length,
         available_bytes: size - offset,
         offset: offset
       }}
    end
  end

  defp validate_pointer(block_number, block_size, size)
       when is_integer(block_number) and block_number >= 1 and
              block_number * block_size + 8 <= size do
    {:ok, block_number * block_size}
  end

  defp validate_pointer(block_number, _block_size, size) do
    {:error, :invalid_memo_pointer, %{memo_block: block_number, memo_bytes: size}}
  end

  defp validate_header(next_block, block_size, size)
       when next_block >= 1 and block_size >= @default_block_size and
              rem(block_size, @default_block_size) == 0 and
              size > (next_block - 1) * block_size and size <= next_block * block_size,
       do: :ok

  defp validate_header(next_block, block_size, size) do
    {:error, :invalid_memo_header,
     %{
       next_block: next_block,
       block_size: block_size,
       actual_bytes: size,
       offset: 0
     }}
  end

  defp normalize_block_size(0), do: @default_block_size
  defp normalize_block_size(block_size), do: block_size

  defp clean_text(payload) do
    text =
      case :binary.match(payload, :binary.compile_pattern(@text_terminators)) do
        {offset, 1} -> binary_part(payload, 0, offset)
        :nomatch -> payload
      end

    String.trim(text)
  end

  defp memo_error(cause, context), do: Error.new(:invalid_memo, cause, context)
end
