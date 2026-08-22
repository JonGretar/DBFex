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
  `1 + sum(field widths)` for fixed-width layouts.
- Records normally start with `0x20` (active) or `0x2A` (deleted). Some writers
  append `0x1A` after the final record; do not require it unless the selected
  profile does.
- Fixed-width names and values are bytes until decoded. NUL padding, space
  padding, and text encoding are separate concerns.
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
- Duplicate field names are legal in real files, often after name truncation.
  Never silently overwrite one value when constructing a map.

## Memo and binary traps

- `.DBT` and `.FPT` are different families. Extension discovery does not select
  a safe parser; use the selected DBF profile and verify the memo header.
- dBASE III DBT, dBASE IV DBT, and FoxPro/VFP FPT differ in block headers,
  termination, block-size rules, and byte order.
- Visual FoxPro FPT header and block integers are big-endian. Common VFP binary
  record fields such as Integer and Currency are little-endian.
- Memo pointers may be space-padded decimal text or a binary integer depending
  on the format and field width.
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

When a source and fixture disagree, preserve the raw bytes, identify the producing
application if possible, and capture the decision in a regression test or ADR.
