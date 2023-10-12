defmodule DBF.Fields do
  defstruct [
    :name,
    :type,
    :length,
    :decimal
  ]
  @type t :: %DBF.Fields{
    name: binary,
    type: binary,
    length: integer,
    decimal: integer
  }
  @moduledoc false

  def parse_fields(field_string) do
    parse_fields(field_string, [])
  end
  defp parse_fields(<<
      name::binary-size(11),
      type::binary-size(1),
      _address::unsigned-integer-32,
      length::unsigned-integer-8,
      decimal::unsigned-integer-8,
      _reserved::binary-size(2),
      _work_area::binary-size(1),
      _reserved2::binary-size(2),
      _set_fields_flag::binary-size(1),
      _reserved3::binary-size(8),
      rest::binary
    >>, acc) do
    # IO.puts("name: #{String.trim(name, <<0>>)} type: #{type} length: #{length} decimal: #{decimal}")
    field = %__MODULE__{
      name: String.trim(name, <<0>>),
      type: type,
      length: length,
      decimal: decimal
    }
    parse_fields(rest, [field | acc])
  end
  defp parse_fields(_bang, acc) do
    Enum.reverse(acc)
  end

end
