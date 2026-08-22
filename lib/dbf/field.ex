defmodule DBF.Field do
  @moduledoc """
  Metadata describing a field in a DBF record.
  """

  defstruct [
    :name,
    :type,
    :length,
    :decimal,
    :address,
    :flags,
    :work_area,
    :set_fields_flag,
    :descriptor_offset,
    :record_offset,
    :decoder,
    :raw_descriptor,
    :reserved
  ]

  @type t :: %__MODULE__{
          name: binary(),
          type: binary(),
          length: non_neg_integer(),
          decimal: non_neg_integer(),
          address: non_neg_integer() | nil,
          flags: byte() | nil,
          work_area: byte() | nil,
          set_fields_flag: byte() | nil,
          descriptor_offset: non_neg_integer(),
          record_offset: pos_integer(),
          decoder: DBF.ValueDecoder.decoder(),
          raw_descriptor: binary(),
          reserved: binary()
        }
end
