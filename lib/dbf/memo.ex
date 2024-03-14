defmodule DBF.Memo do
  alias DBF.DatabaseError
  defstruct [
    :version,
    :device,
    :block_size
  ]
  @type t :: %DBF.Memo{
    version: integer,
    device: File.stream,
    block_size: integer
  }

  @spec open(binary(), integer()) :: DBF.Memo.t() | {:error, DatabaseError.t()}
  def open(path, version) when is_binary(path) and is_integer(version) do
    if File.exists?(path) do
      {:ok, file} = File.open(path, [:read, :binary])
      {:ok, data} = :file.pread(file, 0, 512)
      <<_next_block::little-unsigned-integer-32, block_size::little-unsigned-16,_rest::binary>> = data
      {:ok, %__MODULE__{
        version: version,
        device: file,
        block_size: (if block_size > 0, do: block_size, else: 512)
      }}
    else
      {:error, DatabaseError.new(:enoent)}
    end
  end

  @spec get_block(DBF.Memo.t(), any()) :: binary() | {:error, atom()}
  def get_block(nil, _) do
    {:error, DatabaseError.new(:missing_memo_file)}
  end

  def get_block(%DBF.Memo{version: 0x83, device: dev, block_size: block_size}, block_number) do
    offset = block_number * block_size
    {:ok, raw_data} = :file.pread(dev, offset, 512)
    raw_data |> String.replace([<<31>>], "") |> String.trim()
  end

  def get_block(%DBF.Memo{device: dev, block_size: block_size}, block_number) do
    offset = block_number * block_size
    {:ok, <<_type::binary-size(4), length::little-unsigned-integer-32>>} = :file.pread(dev, offset, 8)
    {:ok, raw_data} = :file.pread(dev, offset+8, length)
    raw_data |> String.replace([<<31>>], "") |> String.trim()
  end


end
