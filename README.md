# DBF

Read DBASE files in Elixir.

At the moment it only supports read.

## Usage

Open a file with open/1 or open/2

```elixir
{:ok, db} = DBF.open("test/dbf_files/bayarea_zipcodes.dbf")
```

The resulting DB follows the enumerable protocol, so you can use all the functions in the Enum module.

So to get all the records of a database you can do:

```elixir
db |> Enum.to_list()
```

The result is a `{status, %{...}}` tuple, where the record status is either
`:record` or `:deleted_record`.

You can get specific rows by using the `DBF.get/2` function.

```elixir
case DBF.get(db, 2) do
  {:record, row} -> IO.inspect(row)
  {:deleted_record, row} -> IO.inspect(row)
  {:error, error} -> IO.warn(Exception.message(error))
end
```

## Format compatibility

Support is evidence-based and applies only to the capabilities exercised by the
checked-in fixtures. A recognized version byte alone does not imply support.

- **Verified** — representative headers, records, and applicable memo values are
  covered by local expected values.
- **Partial** — some real files work, but known format features or value semantics
  remain incomplete.
- **Planned** — fixtures and primary references are recorded, but the format is
  not accepted yet.
- **Not planned** — outside the scope of the read-only table reader.

| Format/profile                      | Version bytes                  | Level       | Notes                                                                                                                   |
| ----------------------------------- | ------------------------------ | ----------- | ----------------------------------------------------------------------------------------------------------------------- |
| FoxBase                             | `0x02`                         | Partial     | Header, schema, and records are exercised; field-level oracle coverage is limited.                                      |
| dBASE III without memo              | `0x03`                         | Partial     | Multiple real files are readable; duplicate field names and encoding semantics remain unresolved in the implementation. |
| dBASE III with DBT memo             | `0x83`                         | Partial     | Basic memo reads work; multi-block and missing-memo behavior need correction.                                           |
| dBASE IV with DBT memo              | `0x8B`                         | Verified    | Representative schema, values, and memo data are covered.                                                               |
| FoxPro and Visual FoxPro tables/FPT | `0x30`, `0x31`, `0x32`, `0xF5` | Planned     | Fixtures cover FPT, autoincrement, variable-width fields, null flags, and CP1251 text.                                  |
| dBASE Level 7-style tables          | `0x8C` fixture                 | Planned     | Extended header/descriptor and memo support are not implemented.                                                        |
| DBF writing                         | —                              | Not planned | Read-only scope.                                                                                                        |
| NDX/MDX/CDX/DCX index reading       | —                              | Not planned | Tracked separately from table reading.                                                                                  |

See `test/support/fixture_manifest.ex` for per-fixture provenance, encoding,
redistribution status, expected-value source, and normative references. The
longer-term implementation sequence is tracked in
[`docs/plans/dbf-reader-roadmap.md`](docs/plans/dbf-reader-roadmap.md).
