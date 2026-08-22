# 0004. Preserve compatible legacy value defaults

- Status: Accepted
- Date: 2026-08-22

## Context

DBFex historically exposed one unconfigured value policy. Character fields were
trimmed strings, numeric fields were floats, and several blank values became
`nil`. Malformed values were inconsistent: numeric junk became `nil`, numeric
prefixes were accepted, and invalid floats, logicals, and dates escaped through
exceptions before being translated into record errors.

The currently accepted FoxBase, dBASE III, and dBASE IV profiles use fixed-width
legacy records and do not carry an explicit per-record null bitmap. Visual
FoxPro null metadata is a separate record-layout capability planned for Phase 4.
Changing existing numeric results or making all malformed legacy data strict by
default would break callers before an opt-in policy exists.

## Decision

Preserve the compatible unconfigured policy for accepted legacy profiles:

- blank character fields decode to `""` after trimming;
- blank numeric, float, logical, date, and memo values decode to `nil`;
- `nil` from these profiles means the field's blank representation and does not
  claim that the source contained an explicit database null;
- valid `N` and `F` values remain floats by default;
- malformed `N` values decode to `nil`, but a numeric prefix followed by junk is
  malformed rather than a valid partial number;
- malformed `F`, `L`, and `D` values return a contextual `:invalid_record` error;
- malformed memo pointers and payloads retain their contextual `:invalid_memo`
  errors.

Value parsing returns explicit results. Exceptions remain only as a defensive
boundary around decoder defects, not ordinary control flow for dates, logicals,
floats, or numerics.

Exact numerics are available through the opt-in `numeric: :exact` policy. It
returns integers for scale-zero `N` fields and `Decimal` values for positive
scales. FoxBase's compact descriptors omit scale metadata, so integer text
returns an integer while text containing a decimal point returns a `Decimal`.
Parsing is bounded by the field width, and malformed values retain the compatible
`nil` result. The default remains `numeric: :float`.

Explicit null metadata and strict or richer permissive decoding require opt-in
policies with documented result semantics. They must not silently alter the
compatible default.

## Consequences

Existing callers continue receiving floats and the established blank values.
Callers that need exact values can opt into integers and `Decimal` without
changing record or error tuple shapes. Malformed numeric suffixes no longer
disappear behind a successful partial parse. Callers cannot distinguish a blank
legacy numeric from malformed numeric text under either numeric representation;
a future data-decoding policy must provide that distinction before claiming
strict or lossless decoding.

Visual FoxPro's null bitmap must be represented separately from blank field
bytes when that record layout is implemented. It must not reinterpret legacy
`nil` values retroactively as explicit nulls.
