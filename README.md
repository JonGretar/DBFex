# DBF

Read FoxBase and dBASE DBF files in Elixir. DBFex is read-only and supports
random access, enumeration, DBT memo files, legacy text encodings, and optional
exact numeric values.

## Installation

Add `dbf_ex` to your dependencies:

```elixir
def deps do
  [
    {:dbf_ex, "~> 0.2.0"}
  ]
end
```

## Quick start

For most reads, use `DBF.with_open/2,3`. It closes the DBF and any memo resource
when the callback returns or raises:

```elixir
records =
  DBF.with_open("customers.dbf", fn db ->
    Enum.to_list(db)
  end)
```

Each element retains its physical record status:

```elixir
{:record, %{"NAME" => "Ada"}}
{:deleted_record, %{"NAME" => "Grace"}}
{:error, %DBF.DatabaseError{}}
```

### Random access with `DBF.get/2`

Record indexes are zero-based:

```elixir
DBF.with_open("customers.dbf", fn db ->
  case DBF.get(db, 2) do
    {:record, row} -> {:ok, row}
    {:deleted_record, row} -> {:deleted, row}
    {:error, error} -> {:error, Exception.message(error)}
  end
end)
```

### Enumeration and streams

An open database implements `Enumerable`, so it works with `Enum` and `Stream`:

```elixir
DBF.with_open("customers.dbf", fn db ->
  Enum.each(db, fn
    {:record, row} -> IO.inspect(row)
    {:deleted_record, row} -> IO.inspect(row, label: "deleted")
    {:error, error} -> IO.warn(Exception.message(error))
  end)
end)
```

Enumeration includes active and deleted records in file order. If a record
cannot be decoded, its error tuple is emitted as the final element.

### Longer-lived access

Use `DBF.open/1,2` directly for suspended enumeration or when the database must
outlive a callback. Pair every successful open with `DBF.close/1`:

```elixir
case DBF.open("customers.dbf") do
  {:ok, db} ->
    try do
      Enum.take(db, 20)
    after
      DBF.close(db)
    end

  {:error, error} ->
    {:error, Exception.message(error)}
end
```

`DBF.open!/1,2` is also available when opening failure should raise a
`DBF.DatabaseError`. Closing is idempotent.

## Decoding options

Options can be passed to `DBF.open/2`, `DBF.open!/2`, and `DBF.with_open/3`:

| Option             | Values                                               | Default  |
| ------------------ | ---------------------------------------------------- | -------- |
| `:memo_file`       | DBT path or `nil` for automatic companion discovery  | `nil`    |
| `:numeric`         | `:float` or `:exact`                                 | `:float` |
| `:encoding`        | `:auto`, `:raw`, `:windows_1251`, or `:windows_1252` | `:auto`  |
| `:encoding_errors` | `:strict`, `:replace`, or `:raw`                     | `:raw`   |

### Exact numeric values

Numeric fields remain floats by default for compatibility. With
`numeric: :exact`, scale-zero values become integers and scaled values become
`Decimal` values:

```elixir
DBF.with_open("orders.dbf", [numeric: :exact], fn db ->
  DBF.get(db, 0)
end)
```

Malformed and blank numeric fields remain `nil` under this policy.

### Text encoding

Known Windows-1251 and Windows-1252 language drivers are decoded to UTF-8.
Missing or unknown drivers preserve raw bytes by default instead of guessing.
A caller override can handle missing or incorrect metadata:

```elixir
DBF.with_open(
  "customers.dbf",
  [encoding: :windows_1251, encoding_errors: :strict],
  fn db -> Enum.to_list(db) end
)
```

The selected policy applies to field names, character values, and textual DBT
memos. Binary and structural values are not decoded as text.

## Error handling

Non-bang operations return `{:error, %DBF.DatabaseError{}}`. Errors include a
stable broad `reason` and may carry useful context such as filename, record
number, field name/type, byte offset, or format version:

```elixir
case DBF.open("customers.dbf") do
  {:ok, db} -> DBF.close(db)
  {:error, %DBF.DatabaseError{reason: reason} = error} ->
    IO.warn("#{reason}: #{Exception.message(error)}")
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

| Format/profile                      | Version bytes                  | Level       | Notes                                                                                                                                                           |
| ----------------------------------- | ------------------------------ | ----------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| FoxBase                             | `0x02`                         | Verified    | All fixture records and `C`/unscaled `N` values are checked, including blanks, exact numerics, and deleted-record behavior.                                     |
| dBASE III without memo              | `0x03`                         | Verified    | All zipcode oracle rows, the full schema, legacy value states, exact numerics, Windows-1252 policies, and ambiguous-schema rejection are covered.               |
| dBASE III with DBT memo             | `0x83`                         | Verified    | Representative complete records, schema, exact numerics, logical states, multi-block memos, pointers, encoding overrides, and companion validation are covered. |
| dBASE IV with DBT memo              | `0x8B`                         | Verified    | Representative schema and values, text policies, declared block sizing, multi-block memos, and companion validation are covered.                                |
| FoxPro and Visual FoxPro tables/FPT | `0x30`, `0x31`, `0x32`, `0xF5` | Planned     | Fixtures cover FPT, autoincrement, variable-width fields, null flags, and CP1251 text.                                                                          |
| dBASE Level 7-style tables          | `0x8C` fixture                 | Planned     | Extended header/descriptor and memo support are not implemented.                                                                                                |
| DBF writing                         | —                              | Not planned | Read-only scope.                                                                                                                                                |
| NDX/MDX/CDX/DCX index reading       | —                              | Not planned | Tracked separately from table reading.                                                                                                                          |

See `test/support/fixture_manifest.ex` for per-fixture provenance, encoding,
redistribution status, expected-value source, and normative references.
