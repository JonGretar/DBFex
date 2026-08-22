defmodule DBF.Error do
  @moduledoc false

  @enforce_keys [:reason]
  defstruct reason: nil, cause: nil, context: %{}

  @type t :: %__MODULE__{
          reason: atom(),
          cause: term(),
          context: map()
        }

  @spec new(atom(), term(), map() | keyword()) :: t()
  def new(reason, cause, context) when is_atom(reason) do
    %__MODULE__{reason: reason, cause: cause, context: context_map(context)}
  end

  @spec add_context(t(), map() | keyword()) :: t()
  def add_context(%__MODULE__{} = error, context) do
    context = Map.merge(context_map(context), error.context)
    %__MODULE__{error | context: context}
  end

  defp context_map(context) when is_map(context), do: context
  defp context_map(context) when is_list(context), do: Map.new(context)
end
