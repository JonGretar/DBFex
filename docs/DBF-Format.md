# DBF/xBase format notes

DBF is a family of related formats, not one fully consistent specification.
Select a format profile from the version byte, flags, layout, and producer
evidence; never infer complete support from the version byte alone.

## Agent checklist

- Treat all offsets and lengths as **byte counts**, not character counts.
- Standard dBASE/FoxPro headers store record count, header length, and record
  length little-endian. Do not generalize that byte order to memo files or every
  binary field.
- For common 32-byte-descriptor layouts, the declared header length points to
  the first record and includes the `0x0D` descriptor terminator. Validate the
  terminator rather than deriving field count from division alone.
- Declared record length includes the one-byte deletion marker. It should equal
  `1 + sum(field widths)` for fixed-width layouts. The currently accepted
  fixed-width profiles reject zero-width field descriptors as invalid structure.
- Records normally start with `0x20` (active) or `0x2A` (deleted). Some writers
  append `0x1A` after the final record; do not require it unless the selected
  profile does.
- Fixed-width names and values are bytes until decoded. NUL padding, space
  padding, and text encoding are separate concerns.
- FoxBase 16-byte field descriptors contain a width but no numeric scale byte.
  Exact numeric decoding must inspect the fixed-width value: integer text becomes
  an integer, while a decimal point preserves a `Decimal` value.
- Microsoft documents language-driver `0xC9` as Windows-1251 and `0x03` as
  Windows-1252. `0x57` is commonly treated as Windows-1252 by DBF readers, while
  some GIS tooling historically labels it ISO-8859-1; retain caller override and
  raw policies for producer disagreements.
- Header date bytes usually mean year since 1900, month, and day, but validate
  dates without bang functions. FoxBASE `0x02` has a different header layout.
- Preserve raw version, table flags, language-driver ID, field flags, and
  reserved bytes needed to diagnose producer-specific variants.
- Validate structure before reading records: file size, header and record
  lengths, record count, descriptor terminator, field widths, offsets, and memo
  pointers.
- Blank, null, invalid, deleted, and unsupported are different states. Visual
  FoxPro nullable fields require per-record null metadata; blank bytes are not
  sufficient.
- Visual FoxPro `0x31` descriptors use flag `0x08` for autoincrement fields;
  bytes 19–22 hold the next little-endian value and byte 23 holds the step.
- Visual FoxPro Currency (`Y`) is a signed little-endian 64-bit integer with an
  implicit scale of 10,000. Decode it exactly rather than through a float.
- `_NullFlags` is a physical system field, not caller data. Assign bits to
  nullable fields in descriptor order and consult the bitmap before decoding
  the corresponding field bytes.
- The `0x32` fixtures use the same system bitmap for variable-width metadata.
  Allocate one stored-length bit for each `V` or `Q` field, followed by its null
  bit when nullable. If the length bit is set, the physical field's final byte
  is the actual length; if clear, that final byte remains value data.
- Current Microsoft documentation lists `0x42` for Varchar/Varbinary/Blob tables,
  while the checked-in independently identified fixture uses `0x32`. Support
  only the evidenced `0x32` profile rather than aliasing the undocumented byte.
  A VFPOLEDB 9 SP2 producer probe also emitted `0x32` after adding `V`, `Q`, and
  `W`, independently corroborating the fixture.
- Duplicate field names are legal in real files, often after name truncation.
  Never silently overwrite one value when constructing a map.

## Organizing variant-specific code

Treat a format as a composition of header layout, descriptor layout, memo family,
record metadata, and field/value capabilities. Do not copy the complete reader
into one module per version, and do not scatter raw version-byte checks through
parsers.

- Keep `DBF.FormatProfile` as the single version-selection point.
- Dispatch parsers on profile-selected layouts or families.
- Put schema parsing, duplicate-name validation, and compiled record offsets in
  `DBF.Schema`; keep `DBF.Field` as one field's metadata.
- Keep genuinely different memo algorithms in `DBF.Memo.DBT3`,
  `DBF.Memo.DBT4`, and `DBF.Memo.FPT` behind a small facade.
- Keep shared header logic together until another layout makes separate modules
  materially clearer.
- Keep record decoding profile-aware through compiled schema metadata, not raw
  version checks.
- Defer value-decoder module boundaries until value, blank/null, encoding, and
  binary/text contracts are settled.
- Prefer plain internal modules with explicit function contracts. Do not add one
  large whole-format behavior whose callbacks combine independently varying
  concerns.

See [`ADR 0003`](https://github.com/JonGretar/DBFex/blob/main/docs/adr/0003-compose-format-variants-by-layout.md).

## Memo and binary traps

- `.DBT` and `.FPT` are different families. Extension discovery does not select
  a safe parser; use the selected DBF profile and verify the memo header.
- dBASE III DBT, dBASE IV DBT, and FoxPro/VFP FPT differ in block headers,
  termination, block-size rules, and byte order.
- Visual FoxPro FPT header and block integers are big-endian. Common VFP binary
  record fields such as Integer and Currency are little-endian.
- Memo pointers may be space-padded decimal text or a binary integer depending
  on the format and field width.
- The verified dBASE IV fixture stores its little-endian block size at DBT header
  offset 20, uses `FF FF 08 00` block signatures, includes the 8-byte block
  header in each declared memo length, and uses `0x1F` as a text terminator.
- The partial FoxPro 2.x fixture stores its big-endian block size at FPT header
  offset 6, uses block type `1` for text, and excludes the 8-byte block header
  from each big-endian declared payload length.
- Microsoft defines FPT block type `0` for Picture data and type `1` for text.
  The VFP 9 SP2 producer fixture stores both binary Memo (`M NOCPTRANS`) and Blob
  (`W`) payloads in type-`1` blocks. Use the DBF field descriptor to decide
  whether type-`1` bytes are decoded as text or preserved as binary; do not
  equate an FPT storage type with final value semantics.
- `dbfread` additionally recognizes FPT type `2` as an Object block. The current
  Picture regression proves type-`0` payload preservation; do not claim
  General/OLE support until a producer fixture establishes its type-`2`
  behavior.
- A memo may span several blocks. Bounds-check `block * block_size`, headers,
  and declared payload lengths before allocating or reading.
- Memo, General, Picture, Blob, and binary-flagged Character/Memo values are not
  interchangeable. Decode only values known to be textual.
- Missing memo files, empty memo pointers, invalid pointers, and truncated memo
  data need distinct outcomes.

## Evidence rules

1. Prefer a primary producer specification.
2. Record disagreements between sources instead of silently choosing one.
3. Treat a fixture as evidence for its producer/version, not the whole family.
4. Cross-check representative files with at least one mature independent reader,
   but store expected values locally so tests have no runtime dependency.
5. Keep synthetic malformed binaries in test helpers; do not hand-edit fixture
   files.

## Primary and high-value references

- [Microsoft: Visual FoxPro table file structure](<https://learn.microsoft.com/en-us/previous-versions/visualstudio/foxpro/st4a0s68(v=vs.71)>) — DBF header, 32-byte field descriptors, flags, deletion marker, and backlink area.
- [Microsoft: Visual FoxPro FPT memo structure](<https://learn.microsoft.com/en-us/previous-versions/visualstudio/foxpro/8599s21w(v=vs.71)>) — authoritative FPT header, block types, lengths, and byte order.
- [dBASE: Level 7 DBF structure](https://www.dbase.com/Knowledgebase/INT/db7_file_fmt.htm) — official 68-byte header, 48-byte descriptors, field properties, and DBT notes.
- [Embarcadero: dBASE III/IV/5 file structures](https://blogs.embarcadero.com/dbase-dbf-file-structure/) — vendor-hosted material derived from dBASE language-reference appendices.
- [Library of Congress DBF format description](https://www.loc.gov/preservation/digital/formats/fdd/fdd000325.shtml) — useful provenance, identifiers, and links; not a byte-level implementation specification.

## Secondary references

- [Erik Bachmann's xBase reference](https://www.clicketyclick.dk/databases/xbase/format/index.html) — broad comparison of older variants, especially [DBT layouts](https://www.clicketyclick.dk/databases/xbase/format/dbt.html). Clearly marks many uncertain observations.
- [Independent Software DBF/DBT/FPT guide](https://www.independent-software.com/dbase-dbf-dbt-file-format.html) — approachable overview and examples; verify memo details against primary sources and fixtures.
- [Kaitai Struct DBF description](https://formats.kaitai.io/dbf/) — concise executable structural model, useful as a baseline but incomplete for the full xBase family.

## Reference implementations

Use these to compare behavior and discover edge cases, not as normative sources:

- [dbase-rs](https://github.com/tmontaigu/dbase-rs) (Rust) — active typed reader/writer with seekable sources, memo support, encoding policies, and structured errors.
- [dbfread](https://github.com/olemb/dbfread) (Python) — unusually readable field and memo parsing; inspect `field_parser.py` and `memo.py`. Its comments also document unresolved ambiguities, so cross-check them.
- [python-dbf](https://github.com/ethanfurman/dbf) (Python) — broad dBASE III, FoxPro, VFP, Clipper, memo, null, and value-semantics coverage.
- [OSGeo Shapelib `dbfopen.c`](https://github.com/OSGeo/shapelib/blob/master/dbfopen.c) (C) — mature defensive I/O, offset checks, deletion handling, and code-page metadata for the shapefile-oriented DBF subset; it is not a general memo/VFP reference.

As of 2026-09-03, these projects do not provide a checked-in fixture covering
VFP9 Varbinary (`Q`) or Blob (`W`). `dbfread` has a VFP `0x30` `C`/`D`/text-`M`
DBF/FPT pair; `dbase-rs` has no FPT test fixture; `python-dbf` has no checked-in
binary fixture and has a reported VFP9 FPT-writing compatibility issue; Shapelib
targets the non-memo shapefile DBF subset.

The repository's manually triggered `generate-vfp9-fixture.yml` workflow uses
the archived Microsoft VFPOLEDB 9 SP2 provider as a producer probe for `V`, `Q`,
binary `C`/`M`, `W`, and `B`. Treat its artifact as unreviewed evidence until
the acceptance checklist in `tools/fixtures/vfp9/README.md` is complete.

When a source and fixture disagree, preserve the raw bytes, identify the producing
application if possible, and capture the decision in a regression test or ADR.
