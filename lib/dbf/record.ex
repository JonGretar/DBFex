defmodule DBF.Record do

  def parse_record(fields, data) do
    parse_record(fields, data, %{})
  end
  defp parse_record(_fields, <<>>, acc) do
    Enum.reverse(acc)
  end
  defp parse_record([field| more_fields], data, acc) do
    <<text::binary-size(field.length), rest::binary>> = data
    value = transpose_field(field.type, text)
    parse_record(more_fields, rest, Map.put(acc, field.name, value))
  end
  defp parse_record(_fields, _data, _acc) do
    throw "Invalid Record"
  end

  defp transpose_field("C", value) do
    value |> String.trim()
  end
  defp transpose_field("F", value) do
    value |> String.trim() |> String.to_float()
  end
  defp transpose_field("I", value) do
    value |> String.trim() |> String.to_integer()
  end
  defp transpose_field("N", value) do
    # TODO: Should we be always returning a float? Or should we be returning an integer if there is no decimal?
    case value |> String.trim() |> Float.parse() do
      {number, _} -> number
      :error -> nil
    end
  end
  defp transpose_field("D", <<year::binary-size(4), month::binary-size(2), day::binary-size(2)>>) do
    Date.from_iso8601!("#{year}-#{month}-#{day}")
  end
  defp transpose_field("D", _) do
    throw "Invalid Date"
  end
  defp transpose_field(type, _value) do
    throw "Unhandled Field Type: #{inspect(type)}"
  end

end
