# 0008. Separate FPT storage types from field semantics

- Status: Accepted
- Date: 2026-09-03

## Context

Microsoft documents FPT block type `0` as Picture and type `1` as Text. It is
tempting to interpret those labels as the final Elixir value type. A VFP 9 SP2
fixture generated through VFPOLEDB disproves that rule: both binary Memo
(`M NOCPTRANS`) and Blob (`W`) payloads are stored in type-`1` blocks, while
their field descriptors require the payloads to remain binary.

Picture (`P`) data is evidenced in type-`0` blocks. General/OLE (`G`) remains
unsupported because no producer fixture yet establishes its expected type-`2`
object representation.

## Decision

Treat the FPT block type as storage validation and the DBF field descriptor as
the source of value semantics:

1. textual Memo, binary Memo, and Blob pointers validate FPT block type `1`;
2. textual Memo payloads pass through the table's text decoder;
3. binary Memo and Blob payloads remain binaries;
4. Picture pointers validate type `0` and remain binaries; and
5. General/OLE stays outside the format profile until producer evidence exists.

Compile these choices into distinct field decoders during schema parsing.
`DBF.Memo.FPT` validates the expected storage block type but does not decide
whether the returned bytes are text.

## Consequences

Binary content is no longer incorrectly required to use an FPT Picture block.
The same FPT type-`1` storage can safely serve text or bytes without guessing
from payload contents. Unexpected block types remain structural memo errors.

Supporting General/OLE later requires a separate decoder and producer-backed
type-`2` fixture; it must not be added by treating every non-text block as an
opaque binary.
