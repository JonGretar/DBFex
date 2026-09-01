defmodule DBF.RecordReader do
  @moduledoc false

  alias DBF.Error
  alias DBF.Record
  alias DBF.Resource

  @spec fetch(DBF.Database.t(), term()) ::
          {DBF.record_status(), DBF.record()} | {:error, Error.t()}
  def fetch(%{number_of_records: total}, record_number)
      when not is_integer(record_number) or record_number < 0 or record_number >= total do
    {:error,
     Error.new(:invalid_record_index, :out_of_bounds, %{
       record_number: record_number,
       record_count: total
     })}
  end

  def fetch(
        %{resource: resource, record_bytes: record_bytes, header_bytes: header_bytes} = db,
        record_number
      ) do
    offset = header_bytes + record_number * record_bytes

    case Resource.read_exact(resource, :table, offset, record_bytes) do
      {:ok, <<" ", data::binary>>} ->
        decode_record(db, :record, data, record_number, offset)

      {:ok, <<"*", data::binary>>} ->
        decode_record(db, :deleted_record, data, record_number, offset)

      {:ok, <<marker, _data::binary>>} ->
        {:error,
         Error.new(:invalid_record, {:unknown_record_marker, marker}, %{
           record_number: record_number,
           offset: offset,
           version: db.version
         })}

      {:error, %Error{} = error} ->
        {:error,
         error
         |> record_read_error()
         |> Error.add_context(%{
           record_number: record_number,
           offset: offset,
           version: db.version
         })}
    end
  end

  defp decode_record(db, status, data, record_number, offset) do
    case Record.parse_record(db, data) do
      {:ok, record} ->
        {status, record}

      {:error, %Error{} = error} ->
        {:error,
         Error.add_context(error, %{
           record_number: record_number,
           offset: offset,
           version: db.version
         })}
    end
  end

  defp record_read_error(%Error{cause: :eof} = error), do: %Error{error | reason: :invalid_record}
  defp record_read_error(%Error{} = error), do: error
end
