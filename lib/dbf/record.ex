defmodule DBF.Record do

  def parse_record(db, data) do
    parse_record(db, db.fields, data, %{})
  end
  defp parse_record(_db, _fields, <<>>, acc) do
    Enum.reverse(acc)
  end
  defp parse_record(db, [field| more_fields], data, acc) do
    <<text::binary-size(field.length), rest::binary>> = data
    value = transpose_field(db, field, text)
    parse_record(db, more_fields, rest, Map.put(acc, field.name, value))
  end
  defp parse_record(_db, _fields, _data, _acc) do
    throw "Invalid Record"
  end

  defp transpose_field(_db, %{type: "C"}, value) do
    value |> String.trim()
  end
  defp transpose_field(_db, %{type: "F"}, value) do
    value |> String.trim() |> String.to_float()
  end
  defp transpose_field(_db, %{type: "I"}, value) do
    value |> String.trim() |> String.to_integer()
  end
  defp transpose_field(_db, %{type: "L"}, value) do
    # Read logical operations.
    # if value is any of YyTt it is TRUE. if it is any of NnFf it is FALSE. Else it's nil
    case value do
      l when l in ["Y", "y", "T", "t"] -> true
      l when l in ["N", "n", "F", "f"] -> false
      l when l in ["?", " "] -> nil
      other -> raise "Illegal logical value: #{other}"
    end
  end
  defp transpose_field(_db, %{type: "N"}, value) do
    # TODO: Should we be always returning a float? Or should we be returning an integer if there is no decimal?
    case value |> String.trim() |> Float.parse() do
      {number, _} -> number
      :error -> nil
    end
  end
  defp transpose_field(db, %{type: "M"}, value) do
    block = value |> String.trim() |> String.to_integer()
    DBF.Memo.get_block(db.memo_file, block)
  end
  defp transpose_field(_db, %{type: "D"}, <<year::binary-size(4), month::binary-size(2), day::binary-size(2)>>) do
    Date.from_iso8601!("#{year}-#{month}-#{day}")
  end
  defp transpose_field(_db, %{type: "D"}, _) do
    throw "Invalid Date"
  end
  defp transpose_field(_db, field, _value) do
    throw "Unhandled Field Type: #{inspect(field)}"
  end

end
