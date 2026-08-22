defmodule DBF.Record do
  @moduledoc false

  alias DBF.DatabaseError
  alias DBF.Error
  alias DBF.ValueDecoder

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
    case ValueDecoder.decode(db, field, raw_value) do
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
end
