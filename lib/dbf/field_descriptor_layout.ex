defmodule DBF.FieldDescriptorLayout do
  @moduledoc false

  @type t :: :foxbase_16 | :dbase_legacy_32

  @spec start(t()) :: 8 | 32
  def start(:foxbase_16), do: 8
  def start(:dbase_legacy_32), do: 32

  @spec size(t()) :: 16 | 32
  def size(:foxbase_16), do: 16
  def size(:dbase_legacy_32), do: 32
end
