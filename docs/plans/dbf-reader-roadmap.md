# DBFex reader roadmap

- Status: Active
- Last updated: 2026-08-22
- Progress: Phases -1 through 3 complete; Phase 4.1 in progress

This is a living implementation roadmap. Durable architectural decisions are
recorded separately under `docs/adr/`.

## Purpose

DBFex should become a dependable, read-only xBase table reader before it grows
into a writer or index engine. The current implementation proved that the basic
approach works, but it mixes format detection, binary layouts, decoding, I/O,
and error handling in ways that make every new variant risky.

This plan favors incremental replacement behind the intended public interface,
not a ground-up rewrite. Phase -1 defines that compatibility perimeter before
tests accidentally freeze implementation details. Unless a versioned release
explicitly says otherwise, preserve:

- `DBF.open/1,2`, `DBF.open!/1,2`, `DBF.get/2`, and `DBF.close/1`;
- the `{:record, map}`, `{:deleted_record, map}`, and error tagged tuples;
- `Enumerable` support for an open `DBF.Database`.

The project is still pre-1.0. This is the appropriate time to classify exposed
struct fields and undocumented functions as stable, intentionally observable,
or internal rather than preserving every accidental interface indefinitely.

## Principles

1. **Parse from specifications, verify with real files.** Record the source for
   every layout and keep the smallest legally distributable fixture that proves
   it.
2. **Select the format once.** A version byte and header flags should select a
   format profile. Header, field, record, and memo parsing should not each
   maintain unrelated version lists.
3. **Never crash on untrusted bytes.** Truncated, corrupt, or unsupported input
   should produce a contextual `DBF.DatabaseError`, not a match error, throw, or
   unrelated exception.
4. **Keep bytes and text distinct.** Decode character data using the table's
   language driver. Do not run arbitrary binary fields through `String`
   functions.
5. **Own resources explicitly.** Every successful open has one corresponding
   close; every failed open closes all files acquired along the way.
6. **Be strict about structure and configurable about data.** Invalid offsets
   and lengths are structural errors. Invalid dates, numbers, logical values,
   and text encodings may eventually support documented strict and permissive
   policies.
7. **Do not claim support from a version byte alone.** Support means the header
   layout, field descriptors, field types, null representation, text encoding,
   and memo family used by that variant are tested.
8. **Preserve intent, not accidents.** Characterization tests should distinguish
   guaranteed compatibility from observed defects. A current crash, leaked
   handle, mutable-looking cursor, or inconsistent error shape is evidence for a
   regression test with a corrected expectation, not automatically a promise.

## What the review found

These are rules to fix, rather than isolated embarrassing lines:

- File operations and binary matches assume success. Short reads and malformed
  headers can escape as `MatchError`, `FunctionClauseError`, `ArgumentError`, or
  `throw`.
- `DBF.open/2` opens the DBF before validating options and does not reliably
  close the DBF or memo handle when a later stage fails.
- Memo discovery is based only on a wildcard extension. Memo layout and
  endianness differ between DBT and FPT families; the current generic parser
  cannot safely represent both.
- Version knowledge is duplicated across `DBF.Database`, `DBF.Field`,
  `DBF.Record`, and `DBF.Memo`.
- Field parsing silently accepts malformed/truncated descriptor data and does
  not verify the descriptor terminator or that field widths match the declared
  record width.
- Record decoding has inconsistent failure behavior: nil fallbacks, returned
  errors, raises, and throws. Errors omit the record number, field name/type,
  and byte offset.
- `DBF.get/2` does not reject negative or non-integer indexes, and its type
  specification omits its actual error result.
- Numeric fields are always converted to floats, losing integer semantics and
  potentially decimal precision. Visual FoxPro integer decoding uses the wrong
  byte order.
- The language-driver/code-page byte is discarded. The current use of
  `String.trim/1` assumes UTF-8, despite an existing CP1251 fixture.
- Blank, null, invalid, and unsupported values are conflated. Visual FoxPro's
  null bitmap is not modeled.
- Duplicate field names overwrite earlier values in the returned map.
- The mutable-looking `Database.position` field is only an Enumerable cursor;
  enumeration behavior can change if a caller modifies this public struct.
- `%DBF.Database{}`, `%DBF.Field{}`, `%DBF.Memo{}`, and exact
  `%DBF.DatabaseError{}` fields are observable even though the intended public
  compatibility perimeter is not documented. Existing tests directly inspect
  database metadata fields and compare error structs.
- `DBF.Database` is simultaneously a public result, parser state, resource
  container, metadata bag, and Enumerable cursor. Its Enumerable implementation
  calls back into `DBF`, creating a dependency cycle and leaking implementation
  knowledge across the seam.
- Metadata required for diagnostics and future support is discarded, including
  table flags, language driver, field flags, autoincrement metadata, and raw
  version information.
- Tests cover happy-path records for four version bytes, but barely cover
  malformed files, I/O failures, missing memos, deleted records, unusual values,
  encodings, or resource cleanup. Several existing fixtures are unused.

## Proposed architecture

Keep `DBF` as the stable public module and deepen the modules behind it:

- A concrete **source/resource module** owns DBF and memo file handles,
  transactional acquisition, positional reads, size checks, and cleanup.
- Resource code supplies bounded binaries to parsers. Header, schema, record,
  and memo parsers do not perform file I/O or require the complete public
  database struct merely to reach a handle.
- A minimal **format profile** is selected during opening from the version byte,
  flags, and structural evidence. It first describes only the header layout,
  field-descriptor layout, memo family, and variant-specific record metadata;
  later phases enrich it with field capabilities and compiled decoders.
- A **schema parser** returns complete field metadata and validates schema and
  record widths.
- A **record decoder** walks a compiled schema and returns decoded values or one
  contextual internal error.
- A **text decoder** applies the language driver and explicit caller policy to
  character and memo text while binary values remain binaries.
- `DBF.Database` becomes an opaque open-table value as far as practical. Any
  metadata intended for callers must have an intentional stable interface;
  parser state, handles, and cursors are implementation details.
- The public module translates internal results into the existing tagged-tuple
  interface. `open!/2` raises only `DBF.DatabaseError`.

Do not create a behavior or adapter merely in anticipation of future variants.
Use one concrete filesystem resource implementation until a second real source
is accepted as a goal. A seam should exist where there are at least two real
layouts or policies, such as DBT III versus DBT IV, DBT versus FPT, or UTF-8
versus a legacy code page.

## Delivery phases

### Phase -1 — Decide the compatibility perimeter

Complete these decisions before characterization tests are written:

- [x] Classify each exposed interface as **stable public**, **observable but
      intentionally unstable**, or **internal**. Include the `DBF` functions,
      `%DBF.Database{}`, `%DBF.Field{}`, `%DBF.Memo{}`,
      `%DBF.DatabaseError{}`, `DBF.has_memo_file?/1`, and currently callable
      parser functions.
- [x] Decide whether callers may rely on database struct fields. Prefer treating
      an open database as opaque and exposing only intentional metadata, using a
      documented pre-1.0 transition if necessary.
- [x] Define error compatibility: outer tagged-tuple shape, stable reason
      categories, contextual fields, exception messages, preservation of
      underlying file reasons, and the behavior of `open!/2`.
- [x] Define resource ownership: which process owns an open database, whether
      handles may be used by other processes, whether `close/1` is idempotent,
      how multiple close failures are reported, and what direct struct copying
      or construction means.
- [x] Define suspension semantics: a suspended enumeration retains live
      resources and remains usable only until the database is explicitly
      closed.
- [x] Define record semantics: zero-based numbering, invalid-index errors,
      active/deleted/unknown markers, whether enumeration includes each status,
      whether `count/1` means physical records, and how enumeration surfaces a
      record error.
- [x] Decide whether a missing required memo fails during `open/2` or only when a
      memo value is read. If both policies are needed, choose and document one
      default.
- [x] Decide the default duplicate-field-name policy. Prefer a schema error over
      silent data loss.
- [x] Decide whether binary or IO-backed sources are a concrete goal. Preserve
      room for positional reads, but do not add a source behavior for a
      hypothetical second adapter.
- [x] Confirm that writing tables and reading indexes remain separate future
      plans rather than requirements of this refactor.
- [x] Record these decisions in
      [`docs/adr/0001-compatibility-perimeter.md`](../adr/0001-compatibility-perimeter.md)
      so Phase 0 tests encode intent rather than inference.

**Exit criterion:** The intended public interface, error contract, record
semantics, and ownership rules are explicit enough to write unambiguous tests.

### Phase 0 — Establish the contract and evidence base

- [x] Add exact public types for intended return values and options; do not model
      accidental raises, throws, or implementation-only struct fields as
      supported behavior.
- [x] Add compatibility tests for all stable public functions and `Enumerable`
      reduce/halt/suspend/count behavior.
- [x] Add separate defect-reproduction tests whose expectations describe the
      corrected result rather than preserving the current crash, throw, leak,
      or malformed value. These are tagged `:known_defect` and excluded by
      default until their owning implementation phase lands.
- [x] Create a fixture manifest containing format/version, producer where known,
      memo family, encoding, provenance, redistribution status, expected support
      level, and the independent source of expected values.
- [x] Exercise every existing fixture at its declared support level and classify
      it as verified, partial, planned, intentionally unsupported, corrupt, or
      reference-only. Full field-level decoding is not required for every
      reference fixture during this phase.
- [x] Add focused synthetic binaries for edge cases that do not justify a full
      fixture. Keep binary construction in test helpers; do not hand-edit binary
      fixtures.
- [x] Add a compatibility table to the README with support levels:
      **verified**, **partial**, **planned**, and **not planned**.
- [x] Record normative or primary format sources in the fixture manifest and
      relevant tests. Add focused citations to parser modules when those parser
      implementations land.

**Exit criterion:** Intended compatibility is protected, defects are visible
without being frozen, fixture evidence is traceable, and support claims are
honest.

### API checkpoint before Phase 1

- [x] Preserve the existing `open`, `open!`, `get`, `close`, tagged-record, and
      `Enumerable` interfaces.
- [x] Add `DBF.with_open/2,3` as the preferred callback-scoped API with
      deterministic cleanup.
- [x] Keep an open `DBF.Database` opaque and reserve public metadata for explicit
      future `metadata/1` or `schema/1` functions justified by caller needs.
- [x] Keep writing and editing behind a separate future abstraction rather than
      adding read-write mode or mutation to `DBF.Database`.

**Exit criterion:** Phase 1 can replace resource internals without reopening the
public reader API or prematurely designing a writer.

### Phase 1 — Build failure-safe parsing foundations

- [x] Validate options before opening any file.
- [x] Introduce one concrete resource module that owns DBF and memo handles,
      positional reads, file-size queries, transactional acquisition, and
      deterministic cleanup. See
      [`ADR 0002`](../adr/0002-use-a-process-backed-resource-owner.md).
- [x] Make opening transactional: close every acquired handle if profile,
      header, schema, encoding, or memo initialization fails.
- [x] Define one contextual internal error representation and translate it to
      `DBF.DatabaseError` only at the public seam. Preserve the original reason
      and add filename, byte offset, record number, field name/type, and version
      where available.
- [x] Select a minimal format profile during header parsing. It must identify the
      header layout, field-descriptor layout, memo family, and record metadata
      needed by currently supported variants.
- [x] Remove scattered version allowlists and generic memo-family guesses as
      their knowledge moves into the selected profile.
- [x] Make header and schema parsers consume bounded binaries and return total
      results rather than performing I/O or requiring the complete database
      struct.
- [x] Replace partial matches, bang conversions, and throws in these parser paths
      with result-returning code.
- [x] Validate header length, record length, record count against file size,
      descriptor terminator, summed field widths, and all legal offsets before
      reading records.
- [x] Preserve raw version, table flags, language-driver ID, and complete field
      descriptors in internal metadata.
- [x] Add cheap table-driven truncation tests at every byte boundary of the
      current header and descriptor layouts. Keep full property and fuzz testing
      for Phase 5.
- [x] Do not introduce a resource behavior until a second real source adapter is
      accepted and implemented.

**Exit criterion:** Opening and structural parsing of current variants use one
selected profile, never leak acquired resources, and return contextual errors
for malformed or truncated structure.

### Phase 2 — Make current format support correct

Organize variant logic by independently selected layouts and capabilities, not by
copying the full reader into `DBase3`, `DBase4`, or `VisualFoxPro` implementations.
See [`ADR 0003`](../adr/0003-compose-format-variants-by-layout.md). The first two
architectural slices are:

- [x] Introduce `DBF.Schema` to own descriptor parsing, validation, duplicate-name
      policy, and compiled record offsets. Keep `DBF.Field` as metadata for one
      field.
- [x] Split materially different memo algorithms into `DBF.Memo.DBT3` and
      `DBF.Memo.DBT4` behind the profile-driven `DBF.Memo` facade. Use plain
      internal modules rather than a whole-format behavior.
- [x] Reject negative, non-integer, and out-of-range record indexes consistently.
- [x] Handle short reads, truncated records, EOF markers, and unknown record
      markers according to the Phase -1 contract.
- [x] Remove `Database.position`; Enumerable begins at zero and carries its
      cursor only in the reducer continuation.
- [x] Ensure `DBF.get/2` and enumeration produce the same record status and error
      shape, including halt and suspension behavior.
- [x] Compile validated field offsets once during opening so record reads cannot
      drift from the declared record width.
- [x] Implement the chosen duplicate-field-name policy in `DBF.Schema`.
- [x] Correct DBT behavior separately in `DBF.Memo.DBT3` and `DBF.Memo.DBT4`,
      including termination, block sizing, pointers, and multi-block values.
- [x] Implement the chosen missing-memo policy and test missing, empty,
      truncated, mismatched, and explicitly supplied memo files.
- [x] Normalize record and memo failures through the contextual internal error
      representation.
- [x] Verify that claimed FoxBASE, dBASE III, and dBASE IV fixtures still produce
      records compatible with the Phase -1 contract.

**Exit criterion:** Currently claimed formats produce compatible records, while
invalid indexes, corrupt records, and memo failures return useful errors without
crashes or resource leaks.

### Phase 3 — Complete value and text semantics

- [x] Classify field decoders as textual or binary before applying trimming,
      encoding, or other `String` operations.
- [x] Compile decoder choices once at open time rather than branching on field
      type for every value.
- [x] Define blank versus null behavior for every supported field type and
      variant. See [ADR 0004](../adr/0004-preserve-compatible-legacy-value-defaults.md).
- [x] Decode `N` as an integer when scale is zero and as an exact decimal when
      precision matters. Because existing callers receive floats, introduce any
      more exact representation through an opt-in mode before considering a
      future breaking default.
- [x] Keep binary numeric fields unsupported in legacy profiles rather than
      applying unverified endianness or signedness. Visual FoxPro's documented
      little-endian integer and currency decoders remain in Phase 4.
- [x] Support current date values without bang functions and define behavior for
      invalid or blank values. Visual FoxPro timestamps remain in Phase 4.
- [x] Distinguish supported character and textual DBT memo fields through
      profile capabilities; keep binary memo/general and binary field kinds
      unsupported until their owning Visual FoxPro profile lands.
- [x] Map known language-driver IDs to documented code pages.
- [x] Add a deliberate encoding option for missing or incorrect driver IDs.
- [x] Decide among strict error, replacement, and raw-binary policies; do not
      silently guess from content. See
      [ADR 0005](../adr/0005-use-explicit-text-encoding-policies.md).
- [x] Decode field names, character fields, and text memos consistently while
      leaving binary values untouched.
- [x] Turn `cp1251.dbf` into a decoder-level regression without enabling its
      planned Visual FoxPro profile, and exercise the Western `0x57` fixture and
      Windows-1252 mapping.
- [x] Implement only the small, explicitly supported Windows-1251 and
      Windows-1252 mapping set; do not require an encoding dependency.
- [x] Add strict, replacement, and raw text-decoding policies after documenting
      their exact result semantics.

**Exit criterion:** Adding a format changes one profile and its decoders rather
than conditionals throughout the project; non-UTF-8 text is predictable, binary
values remain untouched, and callers can identify the value policy used.

### Verification checkpoint before Phase 4

- [x] Verify every FoxBase fixture record and advertised field kind against local
      fixed-width oracle values.
- [x] Verify every dBASE III zipcode record against the independent CSV oracle
      and cover the remaining advertised legacy value states synthetically.
- [x] Verify representative complete dBASE III DBT records, schema, exact
      numerics, logical states, and memo behavior against independent sidecars
      and `dbfread`.
- [x] Promote FoxBase and both dBASE III profiles only after their fixture
      manifests, public tests, README claims, and changelog agree.

**Exit criterion:** The legacy profiles form a verified baseline before FoxPro
and Visual FoxPro add binary fields, FPT memos, timestamps, and null metadata.

### Architecture checkpoint after Phase 3

Track the post-refactor work in
[Architecture deepening — post-Phase 3 cleanup](architecture-deepening.md).
Complete the revised opening extraction, zero-width field policy, and raw-text
fallback characterization before Phase 4 where practical. They preserve the
existing compatibility perimeter and reduce ambiguity before new formats land.

Reassess database representation, the physical record-reader seam, and
field-descriptor layout ownership together with Phase 4. Null bitmaps,
variable-width values, and additional descriptor families should provide the
requirements for those modules; do not add a speculative compiled-record struct
or move resource I/O into the pure `DBF.Record` decoder.

### Phase 4 — Expand formats in evidence-driven order

#### 4.1 FoxPro 2.x and Visual FoxPro baseline

Target version bytes `0xF5` and `0x30` first because the repository already
contains DBF/FPT fixtures for both.

- [x] Implement FPT headers and text blocks with their specified big-endian values.
- [ ] Support and test baseline FoxPro/VFP field types used by the fixtures,
      including little-endian integer/currency values and timestamp values.
- [ ] Support text memos and preserve binary picture/general data as binaries.
- [ ] Parse VFP table flags, code page, field flags, and the optional backlink
      area without treating them as dBASE IV metadata.

#### 4.2 Visual FoxPro autoincrement and variable-width records

Next target `0x31` and `0x32`, for which fixtures also already exist.

- [ ] Parse field flags and autoincrement next-value/step metadata.
- [ ] Decode `Varchar`, `Varbinary`, and `Blob` according to the VFP descriptor
      and per-record length/null metadata.
- [ ] Implement the VFP null bitmap and distinguish null from blank.

#### 4.3 dBASE Level 5 and Level 7

Add these after the 32-byte descriptor families are stable because dBASE 7 uses
a materially different header and 48-byte field descriptors.

- [ ] Add long field names, language-driver name, field properties, and the
      Level 7 descriptor layout.
- [ ] Add timestamp, autoincrement, double, and general/binary field types based
      on primary dBASE documentation.
- [ ] Obtain or generate small, redistributable fixtures with a known producer.

#### 4.4 Less common xBase variants

Consider dBASE SQL table versions, Visual Objects, Clipper extensions,
HiPer-Six/SMT, and additional FoxBASE signatures only in response to real files
and a reliable specification. Do not broaden an allowlist and call that
support.

Indexes (`NDX`, `MDX`, `CDX`) should initially remain out of scope. Reading
records does not require an index, and index parsing is a separate substantial
project. Detect and report their presence as metadata. Revisit index support
only for a concrete use case such as ordered/indexed lookup.

**Exit criterion:** Each advertised variant has a fixture matrix covering its
header, every supported field type, memo behavior where applicable, encoding,
nulls, deleted records, and malformed input.

### Phase 5 — Hardening, usability, and release readiness

- [ ] Extend the focused truncation tests into property-based tests for
      header/schema/record length invariants and decoder inputs.
- [ ] Add fuzz testing with the invariant that arbitrary bytes never crash the
      VM process or leak a file handle.
- [ ] Test large tables without loading them into memory; benchmark random
      access and full enumeration.
- [ ] Confirm concurrent positional reads from one open database are safe and
      document ownership expectations between processes.
- [ ] Add optional record-selection policy only if demanded: include deleted
      records (compatible default), skip them, or return only them.
- [ ] Improve ExDoc with a support matrix, error examples, memo discovery rules,
      encoding examples, and guaranteed value mappings.
- [ ] Add CI fixture/license checks and run compile warnings, formatting,
      tests, Dialyzer, Credo, and docs on supported OTP/Elixir versions.
- [ ] Record user-visible fixes and additions under `CHANGELOG.md`'s
      `[Unreleased]` section as they land.

## Test strategy

Organize tests by behavior rather than only by producer/version:

- **Opening and ownership:** options, missing files, unsupported versions,
  cleanup after each failure stage, idempotent/invalid close behavior.
- **Header and schema:** each layout, flags, code pages, terminators, offsets,
  field widths, duplicate names, truncation, impossible counts.
- **Values:** a table-driven test for every type × blank/null/valid/invalid
  state × relevant format.
- **Records:** active, deleted, unknown marker, first/last/out-of-range,
  truncated data, EOF marker, and schema mismatch.
- **Memos:** DBT III, DBT IV, FPT, empty values, multi-block values, binary
  values, invalid pointers, missing and truncated files.
- **Encoding:** known driver, caller override, unknown driver, invalid byte
  sequence, text versus binary.
- **Public compatibility:** tagged tuples, exception type from bang functions,
  Enumerable count/reduce/halt/suspend, and stable defaults.

Cross-check representative fixtures against at least one independent mature
reader, but keep expected values in this repository so the test suite has no
runtime dependency on another implementation.

## Deferred value-default decisions

Phase -1 settles interface and ownership questions needed to write tests. These
value-level decisions may remain deferred until Phase 3, but their eventual
answers must be explicit and versioned:

1. Should exact numerics remain floats by default for compatibility, or should a
   future major release return integers/decimals according to field metadata?
2. Should malformed field values fail the record, return nil, preserve raw
   bytes, or be controlled by a decoding policy?
3. When permissive decoding is enabled, how can a caller distinguish a blank,
   an invalid value, a replacement-decoded string, and intentionally raw bytes?

## Reference specifications

Prefer primary sources, while retaining secondary references when primary
documentation is unavailable:

- Microsoft, Visual FoxPro table structure:
  <https://learn.microsoft.com/en-us/previous-versions/st4a0s68(v=vs.90)>
- Microsoft, Visual FoxPro FPT memo structure:
  <https://learn.microsoft.com/en-us/previous-versions/visualstudio/foxpro/8599s21w(v=vs.71)>
- dBASE, Level 7 DBF structure:
  <https://www.dbase.com/Knowledgebase/INT/db7_file_fmt.htm>
- Erik Bachmann's xBase format reference:
  <https://www.clicketyclick.dk/databases/xbase/format/dbf.html>

When sources disagree, capture the disagreement in a test or architecture
decision and identify the producing application/version of the fixture. The
bytes in one sample file are evidence, not a complete specification.
