defmodule DBF.Memo do
  alias DBF.Database, as: DB
  defstruct [
    :device,
    :block_size
  ]
  @type t :: %DBF.Memo{
    device: File.stream,
    block_size: integer
  }

  @spec find_memo_file(DBF.Database.t()) :: {:ok, DBF.Database.t()}
  def find_memo_file(%DB{filename: filename}=db) do
    case DBF.options(db, :memo_file) do
      nil ->
        {:ok, %DB{db | memo_file: find_and_open_memo_file(filename) }}
      memo_filename ->
        {:ok, %DB{db | memo_file: open_memo_file(memo_filename) }}
    end
  end

  defp find_and_open_memo_file(db_filename) do
    memo_filename = (db_filename |> Path.rootname() ) <> ".dbt"
    open_memo_file(memo_filename)
  end

  defp open_memo_file(memo_filename) do
    if File.exists?(memo_filename) do
      {:ok, file} = File.open(memo_filename, [:read, :binary])
      {:ok, data} = :file.pread(file, 0, 512)
      <<_next_block::little-unsigned-integer-32, block_size::little-unsigned-16,_rest::binary>> = data
      %__MODULE__{
        device: file,
        block_size: (if block_size > 0, do: block_size, else: 512)
      }
    else
      false
    end
  end

  def get_block(%DBF.Memo{device: dev, block_size: block_size}, block_number) do
    offset = block_number * block_size
    {:ok, <<_type::binary-size(4), length::little-unsigned-integer-32>>} = :file.pread(dev, offset, 8)
    IO.puts("Reading memo block #{block_number} with length #{length} from offset #{offset+8}")
    {:ok, raw_data} = :file.pread(dev, offset+8, length)
    raw_data |> String.replace([<<31>>], "") |> String.trim()
  end


end
