defmodule DBF.DatabaseError do
  defexception [:reason]
  @type t() :: %__MODULE__{reason: atom}

  @impl true
  def message(%__MODULE__{reason: reason}) do
    format_reason(reason)
  end

  def new(reason) do
    %__MODULE__{reason: reason}
  end

  defp format_reason(:missing_memo_file), do: "Missing memo file"
  defp format_reason(:unhandled_field_type), do: "We encountered a field type that we don't know how to handle"
  defp format_reason(:enoent), do: "File not found"

end
