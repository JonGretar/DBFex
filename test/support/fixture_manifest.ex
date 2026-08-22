defmodule DBF.FixtureManifest do
  @moduledoc false

  @references %{
    dbase_iii_iv: "https://blogs.embarcadero.com/dbase-dbf-file-structure/",
    visual_foxpro:
      "https://learn.microsoft.com/en-us/previous-versions/visualstudio/foxpro/st4a0s68(v=vs.71)",
    visual_foxpro_fpt:
      "https://learn.microsoft.com/en-us/previous-versions/visualstudio/foxpro/8599s21w(v=vs.71)",
    dbase_level_7: "https://www.dbase.com/Knowledgebase/INT/db7_file_fmt.htm",
    older_xbase_secondary: "https://www.clicketyclick.dk/databases/xbase/format/index.html"
  }

  @shared_provenance %{
    producer: :unknown,
    origin: :undocumented,
    redistribution: :unverified
  }

  @fixtures [
    %{
      id: :bayarea_zipcodes,
      files: %{
        table: "test/dbf_files/bayarea_zipcodes.dbf",
        expected_values: ["test/dbf_files/bayarea_zipcodes.csv"]
      },
      profile: %{format: :dbase_iii, version: 0x03, memo: :none, encoding: {:ldid, 0x57}},
      provenance: @shared_provenance,
      support: :verified,
      exercise: {:open, %{records: 187, fields: 5}},
      expected_values: {:csv_sidecar, "test/dbf_files/bayarea_zipcodes.csv"},
      normative_sources: [:dbase_iii_iv]
    },
    %{
      id: :cp1251,
      files: %{
        table: "test/dbf_files/cp1251.dbf",
        oracle: ["test/dbf_files/cp1251_summary.txt"]
      },
      profile: %{
        format: :visual_foxpro,
        version: 0x30,
        memo: :none,
        encoding: {:windows_1251, {:ldid, 0xC9}}
      },
      provenance: @shared_provenance,
      support: :planned,
      exercise: {:unsupported_open, 0x30},
      expected_values: {:schema_sidecar, "test/dbf_files/cp1251_summary.txt"},
      normative_sources: [:visual_foxpro]
    },
    %{
      id: :foxbase,
      files: %{
        table: "test/dbf_files/dbase_02.dbf",
        oracle: ["test/dbf_files/dbase_02_summary.txt"]
      },
      profile: %{format: :foxbase, version: 0x02, memo: :none, encoding: :unspecified},
      provenance: @shared_provenance,
      support: :partial,
      exercise: {:open, %{records: 9, fields: 14}},
      expected_values: {:schema_sidecar, "test/dbf_files/dbase_02_summary.txt"},
      normative_sources: [:older_xbase_secondary]
    },
    %{
      id: :dbase_iii,
      files: %{
        table: "test/dbf_files/dbase_03.dbf",
        oracle: ["test/dbf_files/dbase_03_summary.txt"]
      },
      profile: %{format: :dbase_iii, version: 0x03, memo: :none, encoding: {:ldid, 0x00}},
      provenance: @shared_provenance,
      support: :partial,
      exercise: {:open, %{records: 14, fields: 31}},
      expected_values: {:schema_sidecar, "test/dbf_files/dbase_03_summary.txt"},
      normative_sources: [:dbase_iii_iv],
      notes: ["Contains duplicate Point_ID descriptors; current decoding overwrites one value."]
    },
    %{
      id: :visual_foxpro_memo,
      files: %{
        table: "test/dbf_files/dbase_30.dbf",
        memo: "test/dbf_files/dbase_30.fpt",
        oracle: ["test/dbf_files/dbase_30_summary.txt"]
      },
      profile: %{
        format: :visual_foxpro,
        version: 0x30,
        memo: :fpt,
        encoding: {:ldid, 0x03}
      },
      provenance: @shared_provenance,
      support: :planned,
      exercise: {:unsupported_open, 0x30},
      expected_values: {:schema_sidecar, "test/dbf_files/dbase_30_summary.txt"},
      normative_sources: [:visual_foxpro, :visual_foxpro_fpt]
    },
    %{
      id: :visual_foxpro_autoincrement,
      files: %{
        table: "test/dbf_files/dbase_31.dbf",
        oracle: ["test/dbf_files/dbase_31_summary.txt"]
      },
      profile: %{
        format: :visual_foxpro_autoincrement,
        version: 0x31,
        memo: :none,
        encoding: {:ldid, 0x03}
      },
      provenance: @shared_provenance,
      support: :planned,
      exercise: {:unsupported_open, 0x31},
      expected_values: {:schema_sidecar, "test/dbf_files/dbase_31_summary.txt"},
      normative_sources: [:visual_foxpro]
    },
    %{
      id: :visual_foxpro_varchar,
      files: %{
        table: "test/dbf_files/dbase_32.dbf",
        oracle: ["test/dbf_files/dbase_32_summary.txt"]
      },
      profile: %{
        format: :visual_foxpro_varchar,
        version: 0x32,
        memo: :none,
        encoding: {:ldid, 0x03}
      },
      provenance: @shared_provenance,
      support: :planned,
      exercise: {:unsupported_open, 0x32},
      expected_values: {:schema_sidecar, "test/dbf_files/dbase_32_summary.txt"},
      normative_sources: [:visual_foxpro]
    },
    %{
      id: :dbase_iii_memo,
      files: %{
        table: "test/dbf_files/dbase_83.dbf",
        memo: "test/dbf_files/dbase_83.dbt",
        oracle: [
          "test/dbf_files/dbase_83_summary.txt",
          "test/dbf_files/dbase_83_record_0.yml",
          "test/dbf_files/dbase_83_record_9.yml",
          "test/dbf_files/dbase_83_schema_ar.txt",
          "test/dbf_files/dbase_83_schema_sq.txt",
          "test/dbf_files/dbase_83_schema_sq_lim.txt"
        ]
      },
      profile: %{format: :dbase_iii, version: 0x83, memo: :dbt_iii, encoding: {:ldid, 0x00}},
      provenance: @shared_provenance,
      support: :partial,
      exercise: {:open, %{records: 67, fields: 15}},
      expected_values: {:yaml_sidecars, [0, 9]},
      normative_sources: [:dbase_iii_iv, :older_xbase_secondary],
      notes: ["Record 0 YAML contains a longer memo than the current one-block decoder returns."]
    },
    %{
      id: :dbase_iii_missing_memo,
      files: %{
        table: "test/dbf_files/dbase_83_missing_memo.dbf",
        oracle: ["test/dbf_files/dbase_83_missing_memo_record_0.yml"]
      },
      profile: %{format: :dbase_iii, version: 0x83, memo: :missing_dbt, encoding: {:ldid, 0x00}},
      provenance: @shared_provenance,
      support: :verified,
      exercise: {:open_error, :missing_memo_file, 0x83},
      expected_values: {:yaml_sidecar, "test/dbf_files/dbase_83_missing_memo_record_0.yml"},
      normative_sources: [:dbase_iii_iv, :older_xbase_secondary]
    },
    %{
      id: :dbase_iv_memo,
      files: %{
        table: "test/dbf_files/dbase_8b.dbf",
        memo: "test/dbf_files/dbase_8b.dbt",
        oracle: ["test/dbf_files/dbase_8b_summary.txt"]
      },
      profile: %{format: :dbase_iv, version: 0x8B, memo: :dbt_iv, encoding: {:ldid, 0x00}},
      provenance: @shared_provenance,
      support: :verified,
      exercise: {:open, %{records: 10, fields: 6}},
      expected_values: {:schema_sidecar, "test/dbf_files/dbase_8b_summary.txt"},
      normative_sources: [:dbase_iii_iv, :older_xbase_secondary]
    },
    %{
      id: :dbase_level_7,
      files: %{table: "test/dbf_files/dbase_8c.dbf"},
      profile: %{format: :dbase_level_7, version: 0x8C, memo: :missing_dbt, encoding: :cp437},
      provenance: @shared_provenance,
      support: :planned,
      exercise: {:unsupported_open, 0x8C},
      expected_values: :none,
      normative_sources: [:dbase_level_7]
    },
    %{
      id: :foxpro_memo,
      files: %{
        table: "test/dbf_files/dbase_f5.dbf",
        memo: "test/dbf_files/dbase_f5.fpt",
        oracle: ["test/dbf_files/dbase_f5_summary.txt"]
      },
      profile: %{format: :foxpro, version: 0xF5, memo: :fpt, encoding: {:ldid, 0x00}},
      provenance: @shared_provenance,
      support: :planned,
      exercise: {:unsupported_open, 0xF5},
      expected_values: {:schema_sidecar, "test/dbf_files/dbase_f5_summary.txt"},
      normative_sources: [:visual_foxpro_fpt, :older_xbase_secondary]
    },
    %{
      id: :malformed_empty,
      files: %{table: "test/dbf_files/empty.dbf"},
      profile: %{format: :unknown, version: 0x0D, memo: :none, encoding: :not_applicable},
      provenance: @shared_provenance,
      support: :corrupt,
      exercise: {:unsupported_open, 0x0D},
      expected_values: :none,
      normative_sources: [:older_xbase_secondary]
    },
    %{
      id: :foxpro_database_container,
      files: %{
        table: "test/dbf_files/foxprodb/FOXPRO-DB-TEST.DBC",
        memo: "test/dbf_files/foxprodb/FOXPRO-DB-TEST.DCT",
        indexes: ["test/dbf_files/foxprodb/FOXPRO-DB-TEST.DCX"]
      },
      profile: %{
        format: :visual_foxpro_database_container,
        version: 0x30,
        memo: :fpt_family_dct,
        encoding: {:ldid, 0x03}
      },
      provenance: @shared_provenance,
      support: :reference_only,
      exercise: {:unsupported_open, 0x30},
      expected_values: :none,
      normative_sources: [:visual_foxpro, :visual_foxpro_fpt]
    },
    %{
      id: :foxpro_calls,
      files: %{
        table: "test/dbf_files/foxprodb/calls.dbf",
        memo: "test/dbf_files/foxprodb/calls.FPT",
        indexes: ["test/dbf_files/foxprodb/calls.CDX"]
      },
      profile: %{format: :visual_foxpro, version: 0x30, memo: :fpt, encoding: {:ldid, 0x03}},
      provenance: @shared_provenance,
      support: :planned,
      exercise: {:unsupported_open, 0x30},
      expected_values: :none,
      normative_sources: [:visual_foxpro, :visual_foxpro_fpt]
    },
    %{
      id: :foxpro_contacts,
      files: %{
        table: "test/dbf_files/foxprodb/contacts.dbf",
        memo: "test/dbf_files/foxprodb/contacts.FPT",
        indexes: ["test/dbf_files/foxprodb/contacts.CDX"]
      },
      profile: %{format: :visual_foxpro, version: 0x30, memo: :fpt, encoding: {:ldid, 0x03}},
      provenance: @shared_provenance,
      support: :planned,
      exercise: {:unsupported_open, 0x30},
      expected_values: :none,
      normative_sources: [:visual_foxpro, :visual_foxpro_fpt]
    },
    %{
      id: :foxpro_setup,
      files: %{
        table: "test/dbf_files/foxprodb/setup.dbf",
        indexes: ["test/dbf_files/foxprodb/setup.CDX"]
      },
      profile: %{format: :visual_foxpro, version: 0x30, memo: :none, encoding: {:ldid, 0x03}},
      provenance: @shared_provenance,
      support: :planned,
      exercise: {:unsupported_open, 0x30},
      expected_values: :none,
      normative_sources: [:visual_foxpro]
    },
    %{
      id: :foxpro_types,
      files: %{
        table: "test/dbf_files/foxprodb/types.dbf",
        indexes: ["test/dbf_files/foxprodb/types.CDX"]
      },
      profile: %{format: :visual_foxpro, version: 0x30, memo: :none, encoding: {:ldid, 0x03}},
      provenance: @shared_provenance,
      support: :planned,
      exercise: {:unsupported_open, 0x30},
      expected_values: :none,
      normative_sources: [:visual_foxpro]
    },
    %{
      id: :polygon,
      files: %{table: "test/dbf_files/polygon.dbf"},
      profile: %{format: :dbase_iii, version: 0x03, memo: :none, encoding: :not_applicable},
      provenance: @shared_provenance,
      support: :partial,
      exercise: {:open, %{records: 1, fields: 0}},
      expected_values: :none,
      normative_sources: [:dbase_iii_iv]
    },
    %{
      id: :watershed,
      files: %{table: "test/dbf_files/watershed.dbf"},
      profile: %{format: :dbase_iii, version: 0x03, memo: :none, encoding: {:ldid, 0x57}},
      provenance: @shared_provenance,
      support: :partial,
      exercise: {:open, %{records: 33, fields: 5}},
      expected_values: :none,
      normative_sources: [:dbase_iii_iv]
    }
  ]

  def all, do: @fixtures
  def references, do: @references

  def all_paths do
    @fixtures
    |> Enum.flat_map(fn fixture -> fixture.files |> Map.values() |> List.flatten() end)
    |> Enum.sort()
  end
end
