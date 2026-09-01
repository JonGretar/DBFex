# 0006. Use exact currency and profile-aware nulls

- Status: Accepted
- Date: 2026-09-01

## Context

Visual FoxPro `0x31` tables add two value semantics that the accepted legacy
profiles do not have:

- Currency (`Y`) stores a signed little-endian 64-bit integer with an implicit
  scale of four decimal places.
- Nullable field flags assign bits in a per-record `_NullFlags` system field.
  A set bit is an explicit database null regardless of the bytes physically
  stored for that field.

ADR 0004 preserves floats for legacy textual numerics by default because
changing those established results would break callers. It also requires null
metadata to remain distinct from legacy blank bytes. The public record contract
is still a map in a tagged tuple and has no separate value wrapper for null
provenance.

## Decision

Decode Visual FoxPro currency as `Decimal` in every numeric policy. Currency is
an exact binary field kind with a format-defined scale, not a legacy textual
`N` or `F` value whose historical representation must be preserved. The
`:numeric` option therefore continues to govern only textual numeric fields.

Compile nullable-field bit indexes and the physical null-bitmap location into
the schema. During record decoding, consult the bitmap before decoding a
nullable field's physical bytes. Return `nil` for an explicit null.

Treat `_NullFlags` as system-owned record metadata:

- include its width when validating the physical record;
- do not expose it as a caller-visible field or record-map key;
- validate that it has enough bits for all nullable fields.

This amends ADR 0004's anticipated need for a separate opt-in null policy.
Selecting the evidenced `0x31` profile is sufficient to activate its
format-defined null semantics. Existing profiles and their blank-value behavior
remain unchanged.

## Consequences

Currency values retain all four decimal places without floating-point loss,
including the full signed 64-bit storage range. Callers do not need to select
`numeric: :exact` for currency.

Record maps preserve their existing tagged-tuple shape. Within a returned map,
an explicit Visual FoxPro null and a field decoder's blank `nil` have the same
Elixir value. Their source semantics remain different in the parser: only the
null bitmap can suppress decoding of nonblank physical bytes, and legacy blank
values are not reclassified as database nulls.

Adding a future provenance-preserving value wrapper would be a separate,
explicit public policy rather than a retroactive change to these results.
