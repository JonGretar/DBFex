defmodule DBF.DatabaseError do
  defexception [:reason, :further_info]
  @type t() :: %__MODULE__{reason: atom}

  @impl true
  @spec message(DBF.DatabaseError.t()) :: String.t()
  def message(%__MODULE__{reason: reason}) do
    format_reason(reason)
  end

  @doc false
  @spec new(atom()) :: DBF.DatabaseError.t()
  @spec new(atom(), String.t()) :: DBF.DatabaseError.t()
  def new(reason, further_info \\ "") do
    %__MODULE__{reason: reason, further_info: further_info}
  end

  defp format_reason(:missing_memo_file), do: "Missing memo file"
  defp format_reason(:invalid_options), do: "Invalid options provided"
  defp format_reason(:unhandled_field_type), do: "We encountered a field type that we don't know how to handle"
  defp format_reason(:unsupported_version), do: "Database version not supported"
  defp format_reason(:enoent), do: "File not found"
  defp format_reason(_), do: "UNKNOWN ERROR"
end
