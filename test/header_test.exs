defmodule DBF.HeaderTest do
  use ExUnit.Case, async: true

  alias DBF.Error
  alias DBF.FormatProfile
  alias DBF.Header

  describe "parse/3 with a FoxBase header" do
    setup do
      {:ok, profile} = FormatProfile.select(0x02)
      binary = <<0x02, 9::little-16, 0, 0, 0, 42::little-16>>
      %{binary: binary, profile: profile}
    end

    test "parses the fixed layout", %{binary: binary, profile: profile} do
      assert {:ok,
              %Header{
                version: 0x02,
                date: ~D[1900-01-01],
                record_count: 9,
                header_length: 521,
                record_length: 42,
                table_flags: nil,
                language_driver: nil
              }} = Header.parse(binary, profile, 899)
    end

    test "rejects truncation at every byte boundary", %{binary: binary, profile: profile} do
      for boundary <- 0..(byte_size(binary) - 1) do
        truncated = binary_part(binary, 0, boundary)

        assert {:error,
                %Error{
                  reason: :invalid_header,
                  cause: :invalid_header_size,
                  context: %{actual_bytes: ^boundary, offset: ^boundary}
                }} = Header.parse(truncated, profile, 10_000)
      end
    end
  end

  describe "parse/3 with a legacy header" do
    setup do
      {:ok, profile} = FormatProfile.select(0x83)
      binary = legacy_header(0x83, {124, 2, 29}, 3, 97, 12, 0x01, 0x57)
      %{binary: binary, profile: profile}
    end

    test "parses all preserved metadata", %{binary: binary, profile: profile} do
      assert {:ok,
              %Header{
                version: 0x83,
                date: ~D[2024-02-29],
                record_count: 3,
                header_length: 97,
                record_length: 12,
                table_flags: 0x01,
                language_driver: 0x57
              }} = Header.parse(binary, profile, 133)
    end

    test "rejects truncation at every byte boundary", %{binary: binary, profile: profile} do
      for boundary <- 0..(byte_size(binary) - 1) do
        truncated = binary_part(binary, 0, boundary)

        assert {:error,
                %Error{
                  reason: :invalid_header,
                  cause: :invalid_header_size,
                  context: %{actual_bytes: ^boundary, offset: ^boundary}
                }} = Header.parse(truncated, profile, 10_000)
      end
    end
  end

  test "rejects a version that does not match its profile" do
    {:ok, profile} = FormatProfile.select(0x03)
    binary = legacy_header(0x83, {124, 1, 1}, 0, 33, 1, 0, 0)

    assert {:error,
            %Error{
              reason: :invalid_header,
              cause: :version_mismatch,
              context: %{version: 0x83, profile_version: 0x03, offset: 0}
            }} = Header.parse(binary, profile, 33)
  end

  test "rejects invalid dates without raising" do
    {:ok, profile} = FormatProfile.select(0x03)
    binary = legacy_header(0x03, {124, 2, 30}, 0, 33, 1, 0, 0)

    assert {:error,
            %Error{
              reason: :invalid_header,
              cause: {:invalid_date, :invalid_date},
              context: %{offset: 1}
            }} = Header.parse(binary, profile, 33)
  end

  test "rejects invalid declared lengths" do
    {:ok, legacy_profile} = FormatProfile.select(0x03)
    {:ok, foxbase_profile} = FormatProfile.select(0x02)

    assert {:error, %Error{cause: :invalid_header_length, context: %{offset: 8}}} =
             Header.parse(
               legacy_header(0x03, {124, 1, 1}, 0, 32, 1, 0, 0),
               legacy_profile,
               100
             )

    assert {:error, %Error{cause: :invalid_record_length, context: %{offset: 10}}} =
             Header.parse(
               legacy_header(0x03, {124, 1, 1}, 0, 33, 0, 0, 0),
               legacy_profile,
               100
             )

    assert {:error, %Error{cause: :invalid_record_length, context: %{offset: 6}}} =
             Header.parse(<<0x02, 0::little-16, 0::size(24), 0::little-16>>, foxbase_profile, 521)
  end

  test "rejects record data extending past the file" do
    {:ok, profile} = FormatProfile.select(0x03)
    binary = legacy_header(0x03, {124, 1, 1}, 3, 33, 10, 0, 0)

    assert {:error,
            %Error{
              reason: :invalid_header,
              cause: :records_out_of_bounds,
              context: %{required_file_size: 63, file_size: 62, offset: 33}
            }} = Header.parse(binary, profile, 62)
  end

  defp legacy_header(
         version,
         {year, month, day},
         record_count,
         header_length,
         record_length,
         table_flags,
         language_driver
       ) do
    <<version, year, month, day, record_count::little-32, header_length::little-16,
      record_length::little-16, 0::size(16), 0, 0, 0::size(96), table_flags, language_driver,
      0::size(16)>>
  end
end
