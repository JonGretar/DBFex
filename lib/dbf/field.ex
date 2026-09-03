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
    :autoincrement_next,
    :autoincrement_step,
    :work_area,
    :set_fields_flag,
    :descriptor_offset,
    :record_offset,
    :null_bit,
    :variable_length_bit,
    :decoder,
    :raw_descriptor,
    :reserved
  ]

  @type text_decoder ::
          :character
          | :float
          | :logical
          | {:numeric, DBF.numeric_policy() | :exact_unscaled}
          | :varchar
          | :memo
          | :date
  @type binary_decoder ::
          :integer | :currency | :datetime | :text_memo | :binary_memo | :varbinary
  @type decoder ::
          {:text, text_decoder()} | {:binary, binary_decoder()} | {:unsupported, binary()}

  @type t :: %__MODULE__{
          name: binary(),
          type: binary(),
          length: non_neg_integer(),
          decimal: non_neg_integer() | nil,
          address: non_neg_integer() | nil,
          flags: byte() | nil,
          autoincrement_next: non_neg_integer() | nil,
          autoincrement_step: byte() | nil,
          work_area: byte() | nil,
          set_fields_flag: byte() | nil,
          descriptor_offset: non_neg_integer(),
          record_offset: pos_integer(),
          null_bit: non_neg_integer() | nil,
          variable_length_bit: non_neg_integer() | nil,
          decoder: decoder(),
          raw_descriptor: binary(),
          reserved: binary()
        }
end
