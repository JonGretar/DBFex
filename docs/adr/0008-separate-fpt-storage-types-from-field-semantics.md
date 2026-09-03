# 0008. Separate FPT storage types from field semantics

- Status: Accepted
- Date: 2026-09-03
- Amended: 2026-09-03

## Context

Microsoft documents FPT block type `0` as Picture and type `1` as Text. It is
tempting to interpret those labels as the final Elixir value type. A VFP 9 SP2
fixture generated through VFPOLEDB disproves that rule: both binary Memo
(`M NOCPTRANS`) and Blob (`W`) payloads are stored in type-`1` blocks, while
their field descriptors require the payloads to remain binary.

Picture (`P`) data is evidenced in type-`0` blocks. An MIT-licensed Visual
FoxPro demo table from `arquimedescrivelari/foxpages` provides the missing
General/OLE (`G`) evidence: all 18 populated General pointers across 11 records
reference FPT type-`2` object blocks. Microsoft XSource's Ms-PL-licensed
`wzgraph` table provides corresponding FoxPro 2.x `0xF5` evidence: its two
space-padded decimal `G` pointers also reference type-`2` blocks.

## Decision

Treat the FPT block type as storage validation and the DBF field descriptor as
the source of value semantics:

1. textual Memo, binary Memo, and Blob pointers validate FPT block type `1`;
2. textual Memo payloads pass through the table's text decoder;
3. binary Memo and Blob payloads remain binaries;
4. Picture pointers validate type `0` and remain binaries; and
5. General/OLE pointers validate type `2` and return the complete object payload
   as an opaque binary.

Compile these choices into distinct field decoders during schema parsing.
`DBF.Memo.FPT` validates the expected storage block type but does not decide
whether the returned bytes are text. Pointer representation remains a separate
profile decision: Visual FoxPro uses four-byte little-endian pointers while
FoxPro 2.x uses space-padded decimal pointers.

## Consequences

Binary content is no longer incorrectly required to use an FPT Picture block.
The same FPT type-`1` storage can safely serve text or bytes without guessing
from payload contents. Unexpected block types remain structural memo errors.

General/OLE support deliberately stops at safe payload preservation. Parsing or
extracting the proprietary embedded OLE representation is outside the DBF
reader's scope. Treating an unexpected FPT type as interchangeable with an
object block remains invalid.
