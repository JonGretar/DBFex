defmodule DBF.TestFixture do
  @moduledoc false

  def write_temp!(binary, basename \\ "synthetic.dbf") when is_binary(binary) do
    directory =
      Path.join(
        System.tmp_dir!(),
        "dbf_ex_#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(directory)
    path = Path.join(directory, basename)
    File.write!(path, binary)
    path
  end

  def with_record_marker!(source_path, record_index, marker)
      when is_integer(record_index) and record_index >= 0 and byte_size(marker) == 1 do
    binary = File.read!(source_path)

    <<_::binary-size(8), header_bytes::little-unsigned-integer-16,
      record_bytes::little-unsigned-integer-16, _::binary>> = binary

    offset = header_bytes + record_index * record_bytes
    <<prefix::binary-size(offset), _old_marker::binary-size(1), rest::binary>> = binary

    write_temp!(prefix <> marker <> rest, Path.basename(source_path))
  end

  def cleanup(path) do
    path |> Path.dirname() |> File.rm_rf!()
    :ok
  end
end
