# DBF

Read DBASE files in Elixir.

At the moment it only supports read.

## Usage

For callback-scoped reads, use `DBF.with_open/2,3`. It closes the DBF and any
memo resource after the callback returns or raises:

```elixir
records =
  DBF.with_open("test/dbf_files/bayarea_zipcodes.dbf", fn db ->
    Enum.to_list(db)
  end)
```

An open database implements `Enumerable`. Each element is a `{status, values}`
tuple whose status is `:record` or `:deleted_record`.

Use `DBF.get/2` for a specific zero-based record index:

```elixir
DBF.with_open("test/dbf_files/bayarea_zipcodes.dbf", fn db ->
  case DBF.get(db, 2) do
    {:record, row} -> IO.inspect(row)
    {:deleted_record, row} -> IO.inspect(row)
    {:error, error} -> IO.warn(Exception.message(error))
  end
end)
```

For streaming, suspended enumeration, or longer-lived access, use
`DBF.open/1,2` and pair every successful open with `DBF.close/1`.

### Exact numeric values

Numeric fields remain floats by default for compatibility. Opt into exact values
to receive integers for scale-zero fields and `Decimal` values for positive
scales:

```elixir
DBF.with_open("table.dbf", [numeric: :exact], fn db ->
  DBF.get(db, 0)
end)
```

Malformed and blank numeric fields remain `nil` under this value policy.

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

| Format/profile                      | Version bytes                  | Level       | Notes                                                                                                                                                     |
| ----------------------------------- | ------------------------------ | ----------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| FoxBase                             | `0x02`                         | Partial     | Header, schema, and records are exercised; field-level oracle coverage is limited.                                                                        |
| dBASE III without memo              | `0x03`                         | Partial     | Fixed-width records, legacy blank/invalid values, and opt-in exact numerics are covered; ambiguous duplicate-name schemas are rejected; encoding remains. |
| dBASE III with DBT memo             | `0x83`                         | Partial     | Legacy value defaults, exact numerics, multi-block memos, terminators, pointers, and companion validation are covered; encoding remains.                  |
| dBASE IV with DBT memo              | `0x8B`                         | Verified    | Representative schema, legacy value defaults, declared block sizing, multi-block memos, and companion validation are covered.                             |
| FoxPro and Visual FoxPro tables/FPT | `0x30`, `0x31`, `0x32`, `0xF5` | Planned     | Fixtures cover FPT, autoincrement, variable-width fields, null flags, and CP1251 text.                                                                    |
| dBASE Level 7-style tables          | `0x8C` fixture                 | Planned     | Extended header/descriptor and memo support are not implemented.                                                                                          |
| DBF writing                         | —                              | Not planned | Read-only scope.                                                                                                                                          |
| NDX/MDX/CDX/DCX index reading       | —                              | Not planned | Tracked separately from table reading.                                                                                                                    |

See `test/support/fixture_manifest.ex` for per-fixture provenance, encoding,
redistribution status, expected-value source, and normative references.
