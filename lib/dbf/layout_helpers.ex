defmodule DBF.LayoutHelpers do
  @moduledoc false

  @spec descriptor_start(:foxbase_16 | :dbase_legacy_32) :: 8 | 32
  def descriptor_start(:foxbase_16), do: 8
  def descriptor_start(:dbase_legacy_32), do: 32

  @spec descriptor_size(:foxbase_16 | :dbase_legacy_32) :: 16 | 32
  def descriptor_size(:foxbase_16), do: 16
  def descriptor_size(:dbase_legacy_32), do: 32

  @spec byte_size_if_binary(term()) :: non_neg_integer() | nil
  def byte_size_if_binary(binary) when is_binary(binary), do: byte_size(binary)
  def byte_size_if_binary(_binary), do: nil
end
