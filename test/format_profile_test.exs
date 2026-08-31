defmodule DBF.FormatProfileTest do
  use ExUnit.Case, async: true

  alias DBF.Error
  alias DBF.FormatProfile

  test "selects the complete profile for each supported version" do
    expected = [
      {0x02, :foxbase_8, :foxbase_16, :none, :none},
      {0x03, :dbase_legacy_32, :dbase_legacy_32, :none, :none},
      {0x30, :visual_foxpro_32, :visual_foxpro_32, :fpt, :table_flag},
      {0x83, :dbase_legacy_32, :dbase_legacy_32, :dbt_iii, :required},
      {0x8B, :dbase_legacy_32, :dbase_legacy_32, :dbt_iv, :required},
      {0xF5, :dbase_legacy_32, :dbase_legacy_32, :fpt, :required}
    ]

    for {version, header_layout, field_descriptor_layout, memo_family, memo_requirement} <-
          expected do
      assert {:ok,
              %FormatProfile{
                version: ^version,
                header_layout: ^header_layout,
                field_descriptor_layout: ^field_descriptor_layout,
                memo_family: ^memo_family,
                memo_requirement: ^memo_requirement,
                record_layout: :dbase_legacy
              }} = FormatProfile.select(version)
    end
  end

  test "profiles expose only evidenced field capabilities" do
    assert {:ok, foxbase} = FormatProfile.select(0x02)
    assert foxbase.field_kinds == %{"C" => :character, "N" => :numeric_unscaled}

    assert {:ok, no_memo} = FormatProfile.select(0x03)
    refute Map.has_key?(no_memo.field_kinds, "M")
    refute Map.has_key?(no_memo.field_kinds, "I")

    assert {:ok, visual_foxpro} = FormatProfile.select(0x30)
    assert visual_foxpro.field_kinds["I"] == :integer
    assert visual_foxpro.field_kinds["T"] == :datetime
    assert visual_foxpro.field_kinds["M"] == :text_memo_binary_pointer
    refute Map.has_key?(visual_foxpro.field_kinds, "Y")

    for version <- [0x83, 0x8B, 0xF5] do
      assert {:ok, profile} = FormatProfile.select(version)
      assert profile.field_kinds["M"] == :text_memo
      refute Map.has_key?(profile.field_kinds, "I")
      refute Map.has_key?(profile.field_kinds, "Y")
    end
  end

  test "rejects every other version with contextual information" do
    for version <- 0..255, version not in [0x02, 0x03, 0x30, 0x83, 0x8B, 0xF5] do
      assert {:error,
              %Error{
                reason: :unsupported_version,
                context: %{version: ^version}
              }} = FormatProfile.select(version)
    end
  end
end
