defmodule DBF.FormatProfileTest do
  use ExUnit.Case, async: true

  alias DBF.Error
  alias DBF.FormatProfile

  test "selects the complete profile for each supported version" do
    expected = [
      {0x02, :foxbase_8, :foxbase_16, :none},
      {0x03, :dbase_legacy_32, :dbase_legacy_32, :none},
      {0x83, :dbase_legacy_32, :dbase_legacy_32, :dbt_iii},
      {0x8B, :dbase_legacy_32, :dbase_legacy_32, :dbt_iv}
    ]

    for {version, header_layout, field_descriptor_layout, memo_family} <- expected do
      assert {:ok,
              %FormatProfile{
                version: ^version,
                header_layout: ^header_layout,
                field_descriptor_layout: ^field_descriptor_layout,
                memo_family: ^memo_family,
                record_layout: :dbase_legacy
              }} = FormatProfile.select(version)
    end
  end

  test "rejects every other version with contextual information" do
    for version <- 0..255, version not in [0x02, 0x03, 0x83, 0x8B] do
      assert {:error,
              %Error{
                reason: :unsupported_version,
                context: %{version: ^version}
              }} = FormatProfile.select(version)
    end
  end
end
