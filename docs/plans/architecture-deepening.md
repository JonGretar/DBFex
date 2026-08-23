# Architecture deepening — post-Phase 3 cleanup

- Status: Active
- Date: 2026-08-23
- Depends on: Phases -1 through 3 (complete)

The reader refactor succeeded in separating concerns but left the public `DBF`
module owning too much implementation and the open database duplicating parsed
metadata. The remaining candidates are not independent: opening can be deepened
before Phase 4, while database and record-reader representation should be
coordinated with Phase 4's null and variable-width record requirements.

## Execution order

### Before Phase 4

- [x] C — Consolidate duplicated helpers (smallest, lowest-risk, unblocks A and E)
- [x] A — Extract the complete opening operation from `DBF` (biggest leverage)
- [ ] B — Define and enforce zero-width field policy
- [ ] D — Characterize `TextDecoder` raw fallback against ADR 0005

### Reassess with Phase 4 record requirements

- [ ] F — Remove duplicated header/schema projections from `Database`
- [ ] E — Deepen the physical record-reading path behind `DBF.RecordReader`
- [ ] G — Give field-descriptor layouts cohesive ownership

---

## Candidate A: Extract the complete opening operation from DBF

**Files:** `lib/dbf.ex`, `lib/dbf/opening.ex`, `test/opening_safety_test.exs`

Create a deep internal `DBF.Opening` module that owns the complete opening
operation behind one interface: `open(filename, raw_options)`. It validates and
normalizes options before touching the filesystem, owns the table resource
transaction, parses the profile/header/schema, discovers and acquires memo
resources, and constructs `%Database{}`.

This interface preserves ADR 0001's validation and transactional-resource
invariants. An interface that accepts an already acquired resource would be too
late to validate options without splitting opening knowledge across modules.

`DBF` remains the stable public facade. It keeps public types and documentation,
`open!/2` and `with_open/3` lifecycle presentation, and translation from internal
`DBF.Error` values to `DBF.DatabaseError`. Reducing implementation responsibility,
not reaching a target line count, is the acceptance criterion.

- [x] A.1 Create `lib/dbf/opening.ex` with `@moduledoc false` and public `open/2` only
- [x] A.2 Move option defaults, validation, and normalization into `DBF.Opening`
- [x] A.3 Move `Resource.transaction/2` and the complete initialization/memo-discovery path into `DBF.Opening`
- [x] A.4 Keep public error translation and lifecycle presentation in `DBF`
- [x] A.5 Add or preserve regression tests proving invalid options win before missing-file errors and failed opens release every acquired resource
- [x] A.6 Run `mix test`
- [x] A.7 Run `mix precommit`

---

## Candidate B: Define and enforce zero-width field policy

**Files:** `lib/dbf/schema.ex`, `lib/dbf/value_decoder.ex`, schema/value tests

The catch-all `def decode(_db, _field, ""), do: nil` does not handle ordinary
fixed-width blank values; those still contain each field kind's physical blank
bytes and are already covered by ADR 0004. The catch-all handles only a
zero-byte field slice and currently lets a zero-width unsupported field bypass
its compiled decoder.

For accepted fixed-width profiles, decide from format evidence whether any field
kind may legally have width zero. Reject unsupported zero widths during schema
compilation rather than classifying malformed structure as blank data. Future
profiles may declare a zero-width capability if their specification requires it.

- [ ] B.1 Add a regression proving a zero-width unsupported or malformed field cannot decode as `nil`
- [ ] B.2 Document and enforce the accepted profiles' minimum field widths during schema compilation
- [ ] B.3 Remove the global empty-binary shortcut from `ValueDecoder.decode/3`
- [ ] B.4 Preserve tests for actual character, numeric, float, logical, date, and memo blank representations from ADR 0004
- [ ] B.5 Run `mix test`
- [ ] B.6 Run `mix precommit`

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

## Candidate D: Characterize TextDecoder raw fallback

**Files:** `test/text_decoder_test.exs`, `docs/adr/0005-use-explicit-text-encoding-policies.md`

ADR 0005 deliberately defines `encoding_errors: :raw` as an all-or-nothing
fallback: after fixed-width byte padding is removed, an undefined byte in a known
code page returns the complete original byte string. `TextDecoder.decode/3`
trims before passing that byte string to `decode_bytes/6`, so the implementation
already matches the decision.

Appending undefined bytes while continuing to convert surrounding bytes would
create a mixed raw/UTF-8 result and is a different policy, not an architectural
cleanup. If such behavior is needed, introduce a separately named policy and
amend or supersede ADR 0005 before implementation.

- [ ] D.1 Add a test with defined bytes before and after an undefined byte and assert the complete trimmed original byte string is returned
- [ ] D.2 Add a test proving fixed-width padding is removed before raw fallback
- [ ] D.3 Leave `decode_bytes/6` unchanged unless the characterization exposes an ADR mismatch
- [ ] D.4 Run `mix test`
- [ ] D.5 Run `mix precommit`

---

## Candidate E: Deepen the physical record-reading path

**Files:** `lib/dbf.ex`, `lib/dbf/record.ex`, `lib/dbf/record_reader.ex`, `lib/dbf/database.ex`

`DBF.Record.parse_record/2` already hides width validation, compiled field
slicing, fail-fast decoding, and defensive error translation behind a small
interface. By the deletion test it is earning its keep: deleting it would move
that implementation into a caller. It should remain a pure decoder receiving a
bounded record binary, consistent with the reader roadmap.

The shallow seam is instead the physical read path in `DBF.get/2`. Introduce an
internal `DBF.RecordReader.fetch/2` that owns index validation, offset
calculation, bounded resource reads, record-marker interpretation, delegation to
`DBF.Record`, and record-level error context. `DBF.get/2` remains the public
facade and translates the internal error result.

**Status:** Reassess after F and alongside Phase 4 record-layout work. The reader
must accommodate null bitmaps and variable-width metadata without adding raw
version checks.

- [ ] E.1 Create `lib/dbf/record_reader.ex` with `@moduledoc false` and public `fetch/2` only
- [ ] E.2 Move index validation, positional reads, marker handling, and record-level context from `DBF.get/2` into `RecordReader.fetch/2`
- [ ] E.3 Keep binary decoding and field-level context in `DBF.Record.parse_record/2`
- [ ] E.4 Keep public error translation in `DBF.get/2`
- [ ] E.5 Add regression coverage for invalid indexes, markers, truncation, decode failures, and Phase 4 record metadata
- [ ] E.6 Run `mix test`
- [ ] E.7 Run `mix precommit`

---

## Candidate F: Remove duplicated header/schema projections from Database

**Files:** `lib/dbf/database.ex`, `lib/dbf.ex`, `lib/dbf/record.ex`, fixture/public tests

`DBF.Database` duplicates values already owned by parsed structures:
`record_bytes`, `fields`, and `text_decoder` project `%DBF.Schema{}` while
version, date, record count, header length, record length, flags, and language
driver project parsed header data. Adding a passive `%DBF.CompiledRecord{}` would
create another representation and synchronization invariant rather than deepen
a module.

Retain the parsed `%DBF.Header{}` and `%DBF.Schema{}` in the opaque database and
read metadata through those owners. Keep lifecycle state (`resource`, filename,
memo, options, profile) in `%DBF.Database{}`. ADR 0001 permits changing database
fields, but tests that intentionally inspect the opaque value must be updated
together and downstream source compatibility should still be considered.

**Status:** Reassess at the start of Phase 4. New table flags, field metadata,
null metadata, and variable-width records should determine the final retained
shape; do not introduce a second compiled-record struct speculatively.

- [ ] F.1 Inventory every duplicated `Database` projection and its internal/test callers
- [ ] F.2 Retain parsed `header` and `schema` values instead of copying their fields into `Database`
- [ ] F.3 Update `DBF`, `Enumerable`, record/memo readers, and tests to use the owning structures
- [ ] F.4 Verify that Phase 4 null and variable-width metadata has one owner and no raw-version dispatch leaks into record reading
- [ ] F.5 Decide whether the observable-but-unstable struct change merits an `[Unreleased]` changelog note
- [ ] F.6 Run `mix test`
- [ ] F.7 Run `mix precommit`

---

## Candidate G: Give field-descriptor layouts cohesive ownership

**Files:** `lib/dbf/layout_helpers.ex`, `lib/dbf.ex`, `lib/dbf/header.ex`, `lib/dbf/schema.ex`

Candidate C intentionally consolidated duplicated mappings and is complete. Do
not rewrite its history. If Phase 4 adds another descriptor family or more
layout behavior, replace the generic helper seam with a cohesive
`DBF.FieldDescriptorLayout` module owning descriptor start, size, and any
layout-specific structural rules. Do not let unrelated convenience functions
accumulate in a `Helpers` module.

`byte_size_if_binary/1` is error-reporting convenience rather than descriptor
layout behavior. At that point, keep it caller-local or move it only to a module
that owns a broader, demonstrated error-context operation.

**Status:** Deferred trigger. Do not perform this rename solely for aesthetics;
execute it when new descriptor behavior gives the module meaningful depth.

- [ ] G.1 Reassess when Phase 4 introduces the next field-descriptor layout
- [ ] G.2 Create `DBF.FieldDescriptorLayout` with the complete demonstrated layout interface
- [ ] G.3 Move descriptor start/size and related structural rules out of `LayoutHelpers`
- [ ] G.4 Keep unrelated binary-size convenience out of the descriptor-layout module
- [ ] G.5 Update callers and delete `DBF.LayoutHelpers` only when it has no cohesive responsibility left
- [ ] G.6 Run `mix test`
- [ ] G.7 Run `mix precommit`
