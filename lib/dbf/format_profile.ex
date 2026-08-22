defmodule DBF.FormatProfile do
  @moduledoc false

  alias DBF.Error

  @enforce_keys [
    :version,
    :label,
    :header_layout,
    :field_descriptor_layout,
    :memo_family,
    :record_layout
  ]
  defstruct [
    :version,
    :label,
    :header_layout,
    :field_descriptor_layout,
    :memo_family,
    :record_layout
  ]

  @type header_layout :: :foxbase_8 | :dbase_legacy_32
  @type field_descriptor_layout :: :foxbase_16 | :dbase_legacy_32
  @type memo_family :: :none | :dbt_iii | :dbt_iv
  @type record_layout :: :dbase_legacy

  @type t :: %__MODULE__{
          version: byte(),
          label: String.t(),
          header_layout: header_layout(),
          field_descriptor_layout: field_descriptor_layout(),
          memo_family: memo_family(),
          record_layout: record_layout()
        }

  @profiles %{
    0x02 => %{
      version: 0x02,
      label: "FoxBase",
      header_layout: :foxbase_8,
      field_descriptor_layout: :foxbase_16,
      memo_family: :none,
      record_layout: :dbase_legacy
    },
    0x03 => %{
      version: 0x03,
      label: "dBase III without memo file",
      header_layout: :dbase_legacy_32,
      field_descriptor_layout: :dbase_legacy_32,
      memo_family: :none,
      record_layout: :dbase_legacy
    },
    0x83 => %{
      version: 0x83,
      label: "dBase III with memo file",
      header_layout: :dbase_legacy_32,
      field_descriptor_layout: :dbase_legacy_32,
      memo_family: :dbt_iii,
      record_layout: :dbase_legacy
    },
    0x8B => %{
      version: 0x8B,
      label: "dBase IV with memo file",
      header_layout: :dbase_legacy_32,
      field_descriptor_layout: :dbase_legacy_32,
      memo_family: :dbt_iv,
      record_layout: :dbase_legacy
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
