defmodule DBF.DatabaseError do
  @moduledoc """
  Error returned by DBF operations and raised by their bang variants.
  """

  alias DBF.Error

  defexception reason: nil, cause: nil, context: %{}

  @type t() :: %__MODULE__{
          reason: DBF.error_reason(),
          cause: term(),
          context: map()
        }

  @doc false
  @spec from_internal(Error.t()) :: t()
  def from_internal(%Error{} = error) do
    %__MODULE__{reason: error.reason, cause: error.cause, context: error.context}
  end

  @impl true
  @spec message(t()) :: String.t()
  def message(%__MODULE__{} = error) do
    [format_reason(error.reason), format_context(error.context), format_cause(error.cause)]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
  end

  defp format_reason(:file_not_found), do: "File not found."
  defp format_reason(:file_error), do: "File operation failed."
  defp format_reason(:close_failed), do: "Failed to close database resources."
  defp format_reason(:invalid_options), do: "Invalid options."
  defp format_reason(:invalid_record_index), do: "Invalid record index."
  defp format_reason(:unsupported_version), do: "Database version is not supported."
  defp format_reason(:missing_memo_file), do: "Required memo file is missing."
  defp format_reason(:unsupported_field_type), do: "Field type is not supported."
  defp format_reason(:invalid_header), do: "Invalid database header."
  defp format_reason(:invalid_schema), do: "Invalid database schema."
  defp format_reason(:invalid_record), do: "Invalid database record."
  defp format_reason(:invalid_memo), do: "Invalid memo file."
  defp format_reason(reason), do: "Database error: #{inspect(reason)}."

  defp format_context(context) when map_size(context) == 0, do: ""

  defp format_context(context) do
    details =
      [
        context_value(context, :filename, "file", &inspect/1),
        context_value(context, :version, "version", &format_version/1),
        context_value(context, :offset, "byte", &to_string/1),
        context_value(context, :record_number, "record", &to_string/1),
        context_value(context, :field_name, "field", &inspect/1),
        context_value(context, :field_type, "type", &inspect/1)
      ]
      |> Enum.reject(&is_nil/1)

    case details do
      [] -> ""
      details -> "(" <> Enum.join(details, ", ") <> ")"
    end
  end

  defp format_cause(nil), do: ""
  defp format_cause(cause), do: "Cause: #{inspect(cause)}."

  defp context_value(context, key, label, formatter) do
    case Map.fetch(context, key) do
      {:ok, value} -> "#{label}: #{formatter.(value)}"
      :error -> nil
    end
  end

  defp format_version(version) when is_integer(version) and version in 0..255 do
    version
    |> Integer.to_string(16)
    |> String.upcase()
    |> String.pad_leading(2, "0")
    |> then(&"0x#{&1}")
  end

  defp format_version(version), do: inspect(version)
end
