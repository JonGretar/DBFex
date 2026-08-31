# 0005. Use explicit text encoding policies

- Status: Accepted
- Date: 2026-08-22

## Context

Legacy DBF text is stored as bytes and may carry a one-byte language-driver ID.
DBFex previously discarded that ID and applied UTF-8 `String` operations directly
to field names, character values, memo text, and even malformed byte sequences.
Many accepted fixtures have a missing driver, while the Western zipcode fixture
uses `0x57` and the planned Visual FoxPro fixture uses `0xC9` with CP1251 text.

Guessing an encoding from content is unreliable. Failing all tables without a
driver would also break compatible ASCII and raw-byte reads. Encoding behavior
therefore needs an explicit default, caller overrides, and distinguishable error
policies.

## Decision

Compile one text decoder while opening a table and use it consistently for field
names, character values, and textual memo payloads. Fixed-width padding is
removed as bytes before conversion. Numeric and structural bytes are parsed as
bytes, and binary values are never sent through text conversion.

Support this initial mapping set without an encoding dependency:

- language driver `0xC9` maps to Windows-1251;
- language drivers `0x03` and `0x57` map to Windows-1252;
- missing, zero, and unknown drivers have no inferred encoding.

`DBF.open/2` accepts:

- `encoding: :auto | :raw | :windows_1251 | :windows_1252`;
- `encoding_errors: :strict | :replace | :raw`.

The compatible default is `encoding: :auto, encoding_errors: :raw`. Known
drivers decode to UTF-8. Missing or unknown drivers preserve bytes rather than
guessing. For an undefined byte in a known code page, `:strict` returns a
contextual `:invalid_encoding` error, `:replace` inserts U+FFFD, and `:raw`
returns the original byte string. A caller encoding overrides a missing or
incorrect driver ID.

At the time of this decision, the CP1251 fixture remained a planned Visual
FoxPro format and its record bytes were used directly as decoder evidence. Phase
4 later enabled its fixed-width `0x30` profile without changing this encoding
policy.

## Consequences

Existing ASCII data and driverless files retain byte-compatible results by
default. Known CP1251 and CP1252 text becomes predictable UTF-8, and callers can
choose strict validation or replacement without changing record tuple shapes.
Field-name decoding happens before duplicate-name validation, so collisions are
detected on caller-visible names.

The built-in tables intentionally support only two single-byte code pages.
Additional language-driver IDs require documented mappings and regression
evidence. Multibyte encodings may justify a maintained dependency later rather
than expanding custom conversion logic indefinitely.
