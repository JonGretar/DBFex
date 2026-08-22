defmodule DBF.FormatProfile do
  @moduledoc false

  alias DBF.Error

  @enforce_keys [
    :version,
    :label,
    :header_layout,
    :field_descriptor_layout,
    :memo_family,
    :record_layout,
    :field_kinds
  ]
  defstruct [
    :version,
    :label,
    :header_layout,
    :field_descriptor_layout,
    :memo_family,
    :record_layout,
    :field_kinds
  ]

  @type header_layout :: :foxbase_8 | :dbase_legacy_32
  @type field_descriptor_layout :: :foxbase_16 | :dbase_legacy_32
  @type memo_family :: :none | :dbt_iii | :dbt_iv
  @type record_layout :: :dbase_legacy
  @type field_kind ::
          :character | :numeric | :numeric_unscaled | :float | :logical | :date | :text_memo

  @type t :: %__MODULE__{
          version: byte(),
          label: String.t(),
          header_layout: header_layout(),
          field_descriptor_layout: field_descriptor_layout(),
          memo_family: memo_family(),
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

  @profiles %{
    0x02 => %{
      version: 0x02,
      label: "FoxBase",
      header_layout: :foxbase_8,
      field_descriptor_layout: :foxbase_16,
      memo_family: :none,
      record_layout: :dbase_legacy,
      field_kinds: %{"C" => :character, "N" => :numeric_unscaled}
    },
    0x03 => %{
      version: 0x03,
      label: "dBase III without memo file",
      header_layout: :dbase_legacy_32,
      field_descriptor_layout: :dbase_legacy_32,
      memo_family: :none,
      record_layout: :dbase_legacy,
      field_kinds: @legacy_field_kinds
    },
    0x83 => %{
      version: 0x83,
      label: "dBase III with memo file",
      header_layout: :dbase_legacy_32,
      field_descriptor_layout: :dbase_legacy_32,
      memo_family: :dbt_iii,
      record_layout: :dbase_legacy,
      field_kinds: @memo_field_kinds
    },
    0x8B => %{
      version: 0x8B,
      label: "dBase IV with memo file",
      header_layout: :dbase_legacy_32,
      field_descriptor_layout: :dbase_legacy_32,
      memo_family: :dbt_iv,
      record_layout: :dbase_legacy,
      field_kinds: @memo_field_kinds
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
