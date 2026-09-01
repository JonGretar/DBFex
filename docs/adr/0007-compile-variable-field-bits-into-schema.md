# 0007. Compile variable-field bits into schema

- Status: Accepted
- Date: 2026-09-01

## Context

The Visual FoxPro variable-width fixture uses version `0x32`, a `V` field, and
the same hidden `_NullFlags` system field used for nullable records. For every
variable-width field, the system bitmap first allocates a stored-length bit. If
that field is also nullable, its null bit follows.

When the stored-length bit is set, the final byte of the physical field area
contains the actual value length and is not value data. When it is clear, the
complete physical field area is value data. A null bit must take precedence
over both cases.

Field flag `0x04` distinguishes the fixture's binary `V` value from textual
Varchar. Applying text decoding or fixed-width trimming before interpreting
these flags would corrupt binary values and meaningful trailing bytes.

## Decision

Treat the hidden system field as a general record bitmap owned by
`DBF.Schema`, not only as a null bitmap. Compile each field's bitmap positions
during opening:

1. allocate the variable-length bit for a supported `V` field;
2. allocate its null bit next when flag `0x02` is present;
3. allocate ordinary nullable-field bits in descriptor order.

Validate that `_NullFlags` has enough bytes for every allocated bit and omit it
from visible fields.

During record decoding:

1. apply a field's null bit;
2. when its variable-length bit is set, validate and apply the stored length;
3. decode the resulting bytes as text or binary according to field flag
   `0x04`.

Textual Varchar values use the table's text decoder without fixed-width
trimming. Binary values remain binaries. Reject stored lengths larger than the
physical value area instead of returning partial or ambiguous data.

## Consequences

The record map and tagged-tuple API remain unchanged. Text Varchar values are
decoded strings, while binary `V` values are binaries. Full-width values retain
their final byte and textual trailing spaces because the clear bitmap bit says
the complete field is data.

`DBF.Record` remains a bounded decoder driven by compiled metadata and contains
no raw version checks. Future `Q`, Blob, or other variable-width kinds can reuse
the bitmap model only after fixture evidence establishes their value and memo
semantics.
