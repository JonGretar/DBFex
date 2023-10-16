defmodule DBF.Memo do
  defstruct [
    :device,
    :block_size
  ]
  @type t :: %DBF.Memo{
    device: File.stream,
    block_size: integer
  }

  def sense_memo_file(filename) do
    # change the extension to .dbt

    memo_filename = (filename |> Path.rootname() ) <> ".dbt"
    if File.exists?(memo_filename) do
      # IO.puts("Found memo file: #{memo_filename}")
      {:ok, file} = File.open(memo_filename, [:read, :binary])
      {:ok, data} = :file.pread(file, 0, 512)
      <<_next_block::little-unsigned-integer-32, _block_size::little-unsigned-16,_rest::binary>> = data
      ## TODO: Fix the block size to be the correct size.
      %__MODULE__{
        device: file,
        block_size: 512
      }
    else
      nil
    end
  end

  def get_block(%DBF.Memo{device: dev, block_size: block_size}, block_number) do
    offset = block_number * block_size
    {:ok, <<_type::binary-size(4), length::little-unsigned-integer-32>>} = :file.pread(dev, offset, 8)
    #IO.puts("Reading memo block #{block_number} with length #{length} from offset #{offset+8}")
    {:ok, raw_data} = :file.pread(dev, offset+8, length)
    raw_data |> String.replace([<<31>>], "") |> String.trim()
  end


end
