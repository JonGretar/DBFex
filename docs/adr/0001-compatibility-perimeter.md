# 0001. Define the pre-1.0 compatibility perimeter

- Status: Accepted
- Date: 2026-08-22

## Context

DBFex has a small intended API, but its public structs and callable parser functions
also expose implementation details. Before characterization tests are expanded, the
project needs to distinguish supported behavior from details that may change while
the parser is made safe and additional xBase variants are added.

## Decision

### Interface classification

The following interfaces are **stable public** within the pre-1.0 compatibility
perimeter:

- `DBF.open/1,2`, `DBF.open!/1,2`, and `DBF.with_open/2,3`;
- `DBF.get/2` and `DBF.close/1`;
- `Enumerable` support for values returned by `DBF.open/1,2`;
- record results shaped as `{:record, map}`, `{:deleted_record, map}`, or
  `{:error, %DBF.DatabaseError{}}`.

`%DBF.Database{}`, `%DBF.Field{}`, `%DBF.Memo{}`, and
`%DBF.DatabaseError{}` are **observable but intentionally unstable**. An open
`DBF.Database` is an opaque value: callers may pass it to the stable API and
`Enumerable`, but must not construct, copy, update, pattern-match on, or depend on
its fields. Metadata intended to become stable will be exposed through explicit
functions in a later change.

`DBF.has_memo_file?/1` is also observable but intentionally unstable until an
intentional metadata API is designed. Future metadata is exposed through explicit
functions such as `DBF.metadata/1` or `DBF.schema/1`, if concrete caller needs
justify them; direct database fields do not become the metadata API.

The following currently callable parsing and helper functions are **internal** and
may be changed, moved, or made private without compatibility measures:

- `DBF.options/2`;
- `DBF.Database.open_database/1`, `foxpro?/1`, and `well_known_version?/1`;
- `DBF.Field.parse_fields/1`;
- `DBF.Record.parse_record/2`;
- `DBF.Memo.open/2` and `get_block/2`.

### Options and opening

`DBF.open/2` accepts a keyword list. Its only current option is
`memo_file: String.t() | nil`. `nil` requests automatic companion discovery; a
path selects that companion explicitly. Unknown options, invalid option values,
and invalid option containers return a database error and are validated before
any file is opened.

A format that requires a memo companion fails during opening when no usable memo
file is found. Deferred failure while reading a memo value is not the default.

`DBF.open!/1,2` returns the database or raises only `DBF.DatabaseError`.

`DBF.with_open/2,3` is the preferred API for callback-scoped use. It returns the
callback result unchanged after a successful close. An open or close failure is
returned as a database error. If the callback raises, throws, or exits, DBFex
attempts to close all resources before propagating the original failure. The
callback does not own the database and must not close it.

### Errors

Non-bang public operations return errors as `{:error, %DBF.DatabaseError{}}`.
The exception's stable contract is its broad reason category; context may grow
without a breaking change. Initial public reason categories are:

- `:file_not_found`, `:file_error`, and `:close_failed`;
- `:invalid_options` and `:invalid_record_index`;
- `:unsupported_version`, `:missing_memo_file`, and `:unsupported_field_type`;
- `:invalid_header`, `:invalid_schema`, `:invalid_record`, and `:invalid_memo`.

An error preserves an underlying filesystem or parser cause when one exists and
may include filename, byte offset, record number, field name/type, and raw version.
Exact exception text and the concrete context fields are observable but unstable;
messages must remain useful to a person. Adding context does not alter the outer
result shape or reason category.

### Resource ownership

The process that successfully opens a database owns its DBF and memo resources.
Using the value from another process is unsupported. A successful open has one
logical close, and `DBF.close/1` is idempotent: closing an already closed database
returns `:ok`.

Opening is transactional and closes every resource acquired before a failure.
Closing attempts every owned resource even if one close fails. It returns one
`:close_failed` database error containing all close causes rather than losing a
failure. Copying or directly constructing exposed structs does not create or
transfer ownership and is unsupported.

A suspended enumeration retains the live resources and may be resumed until the
database is explicitly closed. Resuming it after close returns a database error;
it must not crash.

### Record and enumeration semantics

Record indexes are zero-based non-negative integers. A negative, non-integer, or
out-of-range index returns `:invalid_record_index`.

A space record marker produces `{:record, map}` and `*` produces
`{:deleted_record, map}`. Any other marker is an `:invalid_record` error; it is not
a third record status. Enumeration includes active and deleted physical records in
file order. `Enumerable.count/1` reports the header's physical record count,
including deleted records.

If decoding a physical record fails, enumeration emits its `{:error,
%DBF.DatabaseError{}}` as the final element and then halts. This keeps errors
visible without silently skipping data or raising from ordinary enumeration.

Duplicate decoded field names are an `:invalid_schema` error during opening rather
than silently overwriting values in the returned map.

### Sources and deferred scope

The concrete goal is filesystem-backed positional reading. Binary and generic IO
sources are not current goals, so no source behavior will be introduced until a
second real source is accepted.

Writing DBF tables and reading index families such as NDX, MDX, CDX, and DCX
remain separate future plans. They are not requirements of the reader refactor.
Future writing or editing uses a separate writer/editor abstraction rather than a
read-write mode or mutation functions on `DBF.Database`. The reader still
preserves ordered schema, flags, encoding metadata, raw version information, and
format-profile boundaries that a future writer could reuse.

## Consequences

Compatibility tests can protect the stable tagged-tuple and Enumerable behavior
without freezing public struct layouts or parser module boundaries. Some current
behavior is deliberately classified as a defect, including atom errors, unrelated
raises, unknown record tuples, missing memos discovered only during record reads,
non-idempotent close, mutable enumeration position, and duplicate-name overwrite.
Those corrected expectations may be recorded as known-defect tests before their
owning implementation phase lands.
