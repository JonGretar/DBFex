defmodule DBF.Field do
  alias DBF.Database
  defstruct [
    :name,
    :type,
    :length,
    :decimal
  ]
  @type t :: %DBF.Field{
    name: binary,
    type: binary,
    length: integer,
    decimal: integer
  }
  @moduledoc false

  def parse_fields(%Database{version: 0x02}=db) do
    {:ok, raw_fields} = :file.pread(db.device, 8, db.header_bytes-32)
    fields = parse_fields_string_foxbase(raw_fields, [])
    {:ok, %Database{db | fields: fields} }
  end
  def parse_fields(db) do
    {:ok, raw_fields} = :file.pread(db.device, 32, db.header_bytes-32)
    fields = parse_fields_string(raw_fields, [])
    {:ok, %Database{db | fields: fields} }
  end

  defp parse_fields_string_foxbase(<<"\r",_::binary>>, acc) do
    Enum.reverse(acc)
  end
  defp parse_fields_string_foxbase(<<
      name::binary-size(11),
      type::binary-size(1),
      length::unsigned-integer-8,
      _junk::binary-size(3),
      rest::binary
    >>, acc) do

    field = %__MODULE__{
      name: String.trim(name, <<0>>),
      type: type,
      length: length,
      decimal: 0
    }
    parse_fields_string_foxbase(rest, [field | acc])
  end
  defp parse_fields_string_foxbase(_bang, acc) do
    Enum.reverse(acc)
  end

  defp parse_fields_string(<<"\r",_::binary>>, acc) do
    Enum.reverse(acc)
  end
  defp parse_fields_string(<<
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
    field = %__MODULE__{
      name: String.trim(name, <<0>>),
      type: type,
      length: length,
      decimal: decimal
    }
    parse_fields_string(rest, [field | acc])
  end
  defp parse_fields_string(_bang, acc) do
    Enum.reverse(acc)
  end

end
