defmodule DBF.FieldDescriptorLayout do
  @moduledoc false

  @type t :: :foxbase_16 | :dbase_legacy_32 | :visual_foxpro_32

  @spec start(t()) :: 8 | 32
  def start(:foxbase_16), do: 8
  def start(:dbase_legacy_32), do: 32
  def start(:visual_foxpro_32), do: 32

  @spec size(t()) :: 16 | 32
  def size(:foxbase_16), do: 16
  def size(:dbase_legacy_32), do: 32
  def size(:visual_foxpro_32), do: 32

  @spec parse_tail(t(), binary()) ::
          {:ok, %{backlink: binary() | nil}} | {:error, atom(), map()}
  def parse_tail(:visual_foxpro_32, backlink) when byte_size(backlink) == 263 do
    backlink =
      case :binary.match(backlink, <<0>>) do
        {0, 1} -> nil
        {length, 1} -> binary_part(backlink, 0, length)
        :nomatch -> backlink
      end

    {:ok, %{backlink: backlink}}
  end

  def parse_tail(layout, _tail) when layout in [:foxbase_16, :dbase_legacy_32] do
    {:ok, %{backlink: nil}}
  end

  def parse_tail(:visual_foxpro_32, backlink) do
    {:error, :invalid_descriptor_tail, %{expected_bytes: 263, actual_bytes: byte_size(backlink)}}
  end
end
