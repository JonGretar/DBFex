defmodule DBF.Record do
  @moduledoc false

  alias DBF.DatabaseError
  alias DBF.Error
  alias DBF.Memo

  @spec parse_record(DBF.Database.t(), binary()) ::
          {:ok, DBF.record()} | {:error, Error.t()}
  def parse_record(%{schema: schema} = db, data)
      when is_binary(data) and byte_size(data) == schema.record_length - 1 do
    Enum.reduce_while(schema.fields, {:ok, %{}}, fn field, {:ok, record} ->
      value_offset = field.record_offset - 1
      raw_value = binary_part(data, value_offset, field.length)

      case read_field_value(db, field, raw_value) do
        {:ok, value} -> {:cont, {:ok, Map.put(record, field.name, value)}}
        {:error, %Error{} = error} -> {:halt, {:error, error}}
      end
    end)
  end

  def parse_record(%{schema: schema}, data) do
    actual_bytes = if is_binary(data), do: byte_size(data), else: nil

    {:error,
     Error.new(:invalid_record, :record_width_mismatch, %{
       expected_bytes: schema.record_length - 1,
       actual_bytes: actual_bytes
     })}
  end

  defp read_field_value(db, field, raw_value) do
    case read_field(db, field, raw_value) do
      {:error, %Error{} = error} ->
        {:error, Error.add_context(error, field_context(field))}

      value ->
        {:ok, value}
    end
  rescue
    error in DatabaseError ->
      {:error,
       Error.new(error.reason, error.cause, Map.merge(field_context(field), error.context))}

    error ->
      {:error,
       Error.new(
         :invalid_record,
         {:field_decode_failed, Exception.message(error)},
         field_context(field)
       )}
  catch
    kind, reason ->
      {:error, Error.new(:invalid_record, {kind, reason}, field_context(field))}
  end

  defp field_context(field) do
    %{
      field_name: field.name,
      field_type: field.type,
      field_offset: field.record_offset
    }
  end

  defp read_field(_db, _field, "") do
    nil
  end

  defp read_field(_db, %{type: "C"}, value) do
    String.trim(value)
  end

  defp read_field(_db, %{type: "V"}, value) do
    String.trim(value)
  end

  defp read_field(_db, %{type: "F"}, value) do
    case String.trim(value) do
      "" -> nil
      new_value -> String.to_float(new_value)
    end
  end

  defp read_field(_db, %{type: "I"}, <<value::signed-big-integer-32>>) do
    value
  end

  defp read_field(_db, %{type: "Y", decimal: decimal}, <<value::signed-little-integer-64>>) do
    value / :math.pow(10, decimal)
  end

  defp read_field(_db, %{type: "L"}, value) do
    case value do
      logical when logical in ["Y", "y", "T", "t"] -> true
      logical when logical in ["N", "n", "F", "f"] -> false
      logical when logical in ["?", " "] -> nil
      other -> raise "Illegal logical value: #{other}"
    end
  end

  defp read_field(_db, %{type: "N"}, value) do
    case value |> String.trim() |> Float.parse() do
      {number, _} -> number
      :error -> nil
    end
  end

  defp read_field(db, %{type: "M"}, value) do
    new_value = String.trim(value)

    case Integer.parse(new_value) do
      {_block, rest} when rest != "" ->
        {:error, Error.new(:invalid_memo, :invalid_memo_pointer, %{raw_pointer: new_value})}

      {block, ""} ->
        Memo.get_block(db.resource, db.memo_file, block)

      :error when new_value == "" ->
        nil

      :error ->
        {:error, Error.new(:invalid_memo, :invalid_memo_pointer, %{raw_pointer: new_value})}
    end
  end

  defp read_field(_db, %{type: "0"}, _value) do
    nil
  end

  defp read_field(_db, %{type: "D"}, "        ") do
    nil
  end

  defp read_field(
         _db,
         %{type: "D"},
         <<year::binary-size(4), month::binary-size(2), day::binary-size(2)>>
       ) do
    Date.from_iso8601!("#{year}-#{month}-#{day}")
  end

  defp read_field(_db, %{type: "D"}, _) do
    throw("Invalid Date")
  end

  defp read_field(_db, _field, _value) do
    raise DatabaseError, reason: :unsupported_field_type
  end
end
