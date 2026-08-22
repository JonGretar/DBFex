defmodule DBF.FixtureManifestTest do
  use ExUnit.Case

  alias DBF.FixtureManifest

  test "the manifest accounts for every fixture file" do
    actual =
      "test/dbf_files/**/*"
      |> Path.wildcard()
      |> Enum.filter(&File.regular?/1)
      |> Enum.sort()

    assert FixtureManifest.all_paths() == actual
  end

  test "every entry records the required evidence" do
    references = FixtureManifest.references()

    for fixture <- FixtureManifest.all() do
      assert is_atom(fixture.id)
      assert fixture.profile.format
      assert fixture.profile.version in 0..255
      assert fixture.profile.memo
      assert fixture.profile.encoding
      assert fixture.provenance.producer
      assert fixture.provenance.origin
      assert fixture.provenance.redistribution

      assert fixture.support in [
               :verified,
               :partial,
               :planned,
               :intentionally_unsupported,
               :corrupt,
               :reference_only
             ]

      assert Map.has_key?(fixture, :expected_values)
      assert fixture.normative_sources != []

      for source <- fixture.normative_sources do
        assert is_binary(Map.fetch!(references, source))
      end
    end
  end

  test "every table is exercised at its declared support level" do
    for fixture <- FixtureManifest.all() do
      exercise(fixture)
    end
  end

  defp exercise(%{files: %{table: path}, profile: %{version: version}, exercise: exercise}) do
    assert <<^version, _::binary>> = File.read!(path)

    case exercise do
      {:open, expected} ->
        assert {:ok, db} = DBF.open(path)

        try do
          assert db.version == version
          assert db.number_of_records == expected.records
          assert length(db.fields) == expected.fields
          assert Enum.count(db) == expected.records
        after
          DBF.close(db)
        end

      {:unsupported_open, ^version} ->
        assert {:error, %DBF.DatabaseError{reason: :unsupported_version}} = DBF.open(path)

      {:header_only, ^version} ->
        assert File.stat!(path).size >= 1

      {:open_error, reason, ^version} ->
        assert {:error, %DBF.DatabaseError{reason: ^reason}} = DBF.open(path)
    end
  end
end
