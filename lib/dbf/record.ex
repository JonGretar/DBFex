defmodule DBF.Record do
  alias DBF.DatabaseError
  alias DBF.Memo

  def parse_record(db, data) do
    parse_record(db, db.fields, data, %{})
  end
  defp parse_record(_db, _fields, <<>>, acc) do
    acc
  end
  defp parse_record(db, [field| more_fields], data, acc) do
    <<raw_value::binary-size(field.length), rest::binary>> = data
    value = read_field(db, field, raw_value)
    parse_record(db, more_fields, rest, Map.put(acc, field.name, value))
  end
  defp parse_record(_db, _fields, _data, _acc) do
    throw "Invalid Record"
  end

  defp read_field(_db, _field, "") do
    nil
  end
  defp read_field(_db, %{type: "C"}, value) do
    value |> String.trim()
  end
  defp read_field(_db, %{type: "V"}, value) do
    value |> String.trim()
  end
  defp read_field(_db, %{type: "F"}, value) do
    case value |> String.trim() do
      "" -> nil
      new_value -> new_value |> String.to_float()
    end
  end
  defp read_field(_db, %{type: "I"}, <<value::signed-big-integer-32>>) do
    value
  end
  defp read_field(_db, %{type: "Y", decimal: decimal}, <<value::signed-little-integer-64>>) do
    value / :math.pow(10, decimal)
  end
  defp read_field(_db, %{type: "L"}, value) do
    # Read logical operations.
    # if value is any of YyTt it is TRUE. if it is any of NnFf it is FALSE. Else it's nil
    case value do
      l when l in ["Y", "y", "T", "t"] -> true
      l when l in ["N", "n", "F", "f"] -> false
      l when l in ["?", " "] -> nil
      other -> raise "Illegal logical value: #{other}"
    end
  end
  defp read_field(_db, %{type: "N"}, value) do
    # TODO: Should we be always returning a float? Or should we be returning an integer if there is no decimal?
    case value |> String.trim() |> Float.parse() do
      {number, _} -> number
      :error -> nil
    end
  end
  defp read_field(%DBF.Database{memo_file: false}, %{type: "M"}, _value) do
    # TODO: Do not raise here
    raise DatabaseError, reason: :missing_memo_file
  end
  defp read_field(db, %{type: "M"}, value) do
    new_value = value |> String.trim()
    if (new_value == "") do
      nil
    else
      block = new_value |> String.to_integer()
      Memo.get_block(db.memo_file, block)
    end
  end
  defp read_field(_db, %{type: "0"}, _value) do
    nil
  end
  defp read_field(_db, %{type: "D"}, "        ") do
    nil
  end
  defp read_field(_db, %{type: "D"}, <<year::binary-size(4), month::binary-size(2), day::binary-size(2)>>) do
    Date.from_iso8601!("#{year}-#{month}-#{day}")
  end
  defp read_field(_db, %{type: "D"}, _) do
    throw "Invalid Date"
  end
  defp read_field(_db, _field, _value) do
    # TODO: Let's say what the erroring field is.
    # TODO: Incorrect raising?
    raise DatabaseError, reason: :unhandled_field_type
  end

end
