defmodule DBF.FormatProfile do
  @moduledoc false

  alias DBF.Error

  @enforce_keys [
    :version,
    :label,
    :header_layout,
    :field_descriptor_layout,
    :memo_family,
    :memo_requirement,
    :record_layout,
    :field_kinds
  ]
  defstruct [
    :version,
    :label,
    :header_layout,
    :field_descriptor_layout,
    :memo_family,
    :memo_requirement,
    :record_layout,
    :field_kinds
  ]

  @type header_layout :: :foxbase_8 | :dbase_legacy_32 | :visual_foxpro_32
  @type field_descriptor_layout :: DBF.FieldDescriptorLayout.t()
  @type memo_family :: :none | :dbt_iii | :dbt_iv | :fpt
  @type memo_requirement :: :none | :required | :table_flag
  @type record_layout ::
          :dbase_legacy | :visual_foxpro_nullable | :visual_foxpro_variable
  @type field_kind ::
          :character
          | :numeric
          | :numeric_unscaled
          | :float
          | :logical
          | :date
          | :text_memo
          | :integer
          | :currency
          | :double
          | :variable
          | :datetime
          | :text_memo_binary_pointer
          | :binary_memo_pointer
          | :picture_memo_pointer
          | :general_memo_pointer
          | :general_memo_text_pointer

  @type t :: %__MODULE__{
          version: byte(),
          label: String.t(),
          header_layout: header_layout(),
          field_descriptor_layout: field_descriptor_layout(),
          memo_family: memo_family(),
          memo_requirement: memo_requirement(),
          record_layout: record_layout(),
          field_kinds: %{binary() => field_kind()}
        }

  @legacy_field_kinds %{
    "C" => :character,
    "N" => :numeric,
    "F" => :float,
    "L" => :logical,
    "D" => :date
  }

  @memo_field_kinds Map.put(@legacy_field_kinds, "M", :text_memo)
  @foxpro_2_field_kinds Map.put(@memo_field_kinds, "G", :general_memo_text_pointer)
  @visual_foxpro_field_kinds Map.merge(@legacy_field_kinds, %{
                               "B" => :double,
                               "G" => :general_memo_pointer,
                               "I" => :integer,
                               "M" => :text_memo_binary_pointer,
                               "P" => :picture_memo_pointer,
                               "T" => :datetime
                             })
  @visual_foxpro_autoincrement_field_kinds Map.put(
                                             @visual_foxpro_field_kinds,
                                             "Y",
                                             :currency
                                           )
  @visual_foxpro_variable_field_kinds Map.merge(
                                        @visual_foxpro_autoincrement_field_kinds,
                                        %{
                                          "Q" => :variable,
                                          "V" => :variable,
                                          "W" => :binary_memo_pointer
                                        }
                                      )

  @profiles %{
    0x02 => %{
      version: 0x02,
      label: "FoxBase",
      header_layout: :foxbase_8,
      field_descriptor_layout: :foxbase_16,
      memo_family: :none,
      memo_requirement: :none,
      record_layout: :dbase_legacy,
      field_kinds: %{"C" => :character, "N" => :numeric_unscaled}
    },
    0x03 => %{
      version: 0x03,
      label: "dBase III without memo file",
      header_layout: :dbase_legacy_32,
      field_descriptor_layout: :dbase_legacy_32,
      memo_family: :none,
      memo_requirement: :none,
      record_layout: :dbase_legacy,
      field_kinds: @legacy_field_kinds
    },
    0x30 => %{
      version: 0x30,
      label: "Visual FoxPro",
      header_layout: :visual_foxpro_32,
      field_descriptor_layout: :visual_foxpro_32,
      memo_family: :fpt,
      memo_requirement: :table_flag,
      record_layout: :dbase_legacy,
      field_kinds: @visual_foxpro_field_kinds
    },
    0x31 => %{
      version: 0x31,
      label: "Visual FoxPro with autoincrement",
      header_layout: :visual_foxpro_32,
      field_descriptor_layout: :visual_foxpro_32,
      memo_family: :fpt,
      memo_requirement: :table_flag,
      record_layout: :visual_foxpro_nullable,
      field_kinds: @visual_foxpro_autoincrement_field_kinds
    },
    0x32 => %{
      version: 0x32,
      label: "Visual FoxPro with variable-width fields",
      header_layout: :visual_foxpro_32,
      field_descriptor_layout: :visual_foxpro_32,
      memo_family: :fpt,
      memo_requirement: :table_flag,
      record_layout: :visual_foxpro_variable,
      field_kinds: @visual_foxpro_variable_field_kinds
    },
    0x83 => %{
      version: 0x83,
      label: "dBase III with memo file",
      header_layout: :dbase_legacy_32,
      field_descriptor_layout: :dbase_legacy_32,
      memo_family: :dbt_iii,
      memo_requirement: :required,
      record_layout: :dbase_legacy,
      field_kinds: @memo_field_kinds
    },
    0x8B => %{
      version: 0x8B,
      label: "dBase IV with memo file",
      header_layout: :dbase_legacy_32,
      field_descriptor_layout: :dbase_legacy_32,
      memo_family: :dbt_iv,
      memo_requirement: :required,
      record_layout: :dbase_legacy,
      field_kinds: @memo_field_kinds
    },
    0xF5 => %{
      version: 0xF5,
      label: "FoxPro 2.x for DOS/Windows with memo file",
      header_layout: :dbase_legacy_32,
      field_descriptor_layout: :dbase_legacy_32,
      memo_family: :fpt,
      memo_requirement: :required,
      record_layout: :dbase_legacy,
      field_kinds: @foxpro_2_field_kinds
    }
  }

  @spec select(term()) :: {:ok, t()} | {:error, Error.t()}
  def select(version) do
    case Map.fetch(@profiles, version) do
      {:ok, profile} ->
        {:ok, struct(__MODULE__, profile)}

      :error ->
        {:error, Error.new(:unsupported_version, nil, %{version: version})}
    end
  end
end
