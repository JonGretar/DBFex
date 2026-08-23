# Architecture deepening — post-Phase 3 cleanup

- Status: Active
- Date: 2026-08-23
- Depends on: Phases -1 through 3 (complete)

The reader refactor succeeded in separating concerns but left the public DBF
module shallow and a few internal modules with duplicated helpers. These
candidates are independent of the Phase 4 format-expansion work and can be
tackled in any order.

## Execution order

- [x] C — Consolidate duplicated helpers (smallest, lowest-risk, unblocks A and E)
- [ ] A — Extract the opening pipeline from DBF (biggest leverage)
- [ ] B — Deepen ValueDecoder with per-kind blank policies
- [ ] D — Make TextDecoder raw-fallback explicit (evaluate against existing tests)
- [ ] F — Compile header/schema into a flat compiled-record struct (evaluate benefit)
- [ ] E — Collapse DBF.Record (only if A is done and the pipeline is a natural home)

---

## Candidate A: Extract the opening pipeline from DBF

**Files:** `lib/dbf.ex`, `lib/dbf/database.ex`

Extract `initialize_database/3`, `read_version/1`, `read_schema/3`,
`read_structure/4`, `initialize_memo/6`, `acquire_and_initialize_memo/5`,
`find_memo_probe/3`, `find_record_memo_probe/4`, `parse_memo_probe/5`,
`memo_paths/2`, `validate_options/1`, `validate_option_values/1`, and all
individual `validate_*` helpers into a new internal module `DBF.OpeningPipeline`.

`DBF` becomes a thin facade (~80 lines). The pipeline module exposes one
function — `open/3` — that takes a resource, filename, and options and returns
`{:ok, %Database{}}` or an error.

- [ ] A.1 Create `lib/dbf/opening_pipeline.ex` with `@moduledoc false`
- [ ] A.2 Move all listed functions into the new module, keeping them private except `open/3`
- [ ] A.3 In `DBF`, replace the inline pipeline with a call to `OpeningPipeline.open(resource, filename, options)`
- [ ] A.4 Run `mix test`
- [ ] A.5 Run `mix precommit`

---

## Candidate B: Deepen ValueDecoder with per-kind blank policies

**Files:** `lib/dbf/value_decoder.ex`

Remove the catch-all `def decode(_db, _field, "")` clause. Handle blank values
in each field-kind clause explicitly. The `decode/3` interface narrows to a
dispatch on compiled decoder tuples, with each clause owning its own blank
policy.

- [ ] B.1 Remove `def decode(_db, _field, ""), do: nil`
- [ ] B.2 Add per-kind blank clauses: `:character` → `""`, `:float` → `nil`, `:logical` → `nil`, `:date` → `nil`, `:memo` → `nil`, `{:numeric, _}` → `nil`
- [ ] B.3 Run `mix test`
- [ ] B.4 Run `mix precommit`

---

## Candidate C: Consolidate duplicated helper functions

**Files:** `lib/dbf.ex`, `lib/dbf/header.ex`, `lib/dbf/schema.ex`

`descriptor_start/1` is defined identically in `dbf.ex:566-567` and
`schema.ex:241-242`. `byte_size_if_binary/1` is defined identically in
`header.ex:229-230` and `schema.ex:247-248`. `descriptor_size/1` is layout-only
in `schema.ex:244-245`. Create `lib/dbf/layout_helpers.ex` and update all
callers.

- [x] C.1 Create `lib/dbf/layout_helpers.ex` with `descriptor_start/1`, `descriptor_size/1`, and `byte_size_if_binary/1`
- [x] C.2 Remove `descriptor_start/1` from `dbf.ex` and `schema.ex`
- [x] C.3 Remove `byte_size_if_binary/1` from `header.ex` and `schema.ex`
- [x] C.4 Remove `descriptor_size/1` from `schema.ex`
- [x] C.5 Update all callers to use `LayoutHelpers`
- [x] C.6 Run `mix test`
- [x] C.7 Run `mix precommit`

---

## Candidate D: Make TextDecoder raw-fallback explicit

**Files:** `lib/dbf/text_decoder.ex`

When `errors: :raw` and an invalid byte is hit, `decode_bytes/6` returns
`{:ok, original}` — the untrimmed, pre-processed binary. This leaks internal
processing state. For `:raw` mode, pass undefined bytes through as literal bytes
rather than short-circuiting to the original.

**Status:** Worth exploring. This is a behavioral change, not a pure refactor.
Verify existing tests don't rely on the short-circuit before proceeding.

- [ ] D.1 In `decode_bytes/6`, change the `:raw` clause to append raw bytes and continue instead of returning `{:ok, original}`
- [ ] D.2 Add a test that verifies `:raw` mode preserves invalid bytes in place
- [ ] D.3 Run `mix test`
- [ ] D.4 Run `mix precommit`

---

## Candidate E: Collapse DBF.Record into the record pipeline

**Files:** `lib/dbf/record.ex`, `lib/dbf.ex`

`DBF.Record` is 65 lines with one public function, `parse_record/2`. The
interface is nearly as wide as the implementation. Inline the field iteration
and error handling into the pipeline.

**Status:** Speculative. Only do this if Candidate A is complete and the
pipeline module is a natural home.

- [ ] E.1 Move `parse_record/2` and `read_field_value/3` into the opening pipeline module (or `dbf.ex` if A is not done)
- [ ] E.2 Delete `lib/dbf/record.ex`
- [ ] E.3 Run `mix test`
- [ ] E.4 Run `mix precommit`

---

## Candidate F: Compile header and schema into a flat compiled-record struct

**Files:** `lib/dbf/database.ex`, `lib/dbf.ex`, `lib/dbf/record.ex`

The `DBF.Database` struct has 15 fields mixing lifecycle concerns and compiled
record data. Group the compiled record-reader fields (header_bytes, record_bytes,
record_count, fields, text_decoder) into a nested struct. Record reading uses
the nested struct; the outer struct manages lifecycle.

**Status:** Worth exploring. ADR 0001 says `Database` is opaque, so this is
compatible. Evaluate whether the extra struct adds clarity or just moves the
grab-bag one level down.

- [ ] F.1 Create `lib/dbf/compiled_record.ex` with `header_bytes`, `record_bytes`, `record_count`, `fields`, `text_decoder`
- [ ] F.2 Populate it during `initialize_database/3` instead of spreading fields across `Database`
- [ ] F.3 Update `DBF.get/2` and the `Enumerable` implementation to destructure `compiled_record`
- [ ] F.4 Run `mix test`
- [ ] F.5 Run `mix precommit`
