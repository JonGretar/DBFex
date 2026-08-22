# 0003. Compose format variants by layout and capability

- Status: Accepted
- Date: 2026-08-22

## Context

xBase variants overlap unevenly. dBASE III and IV share much of their table
header and field-descriptor structure but use different DBT memo layouts.
Visual FoxPro reuses parts of the legacy table shape while adding field flags,
null metadata, variable-width records, FPT memos, and additional field types.
FoxBase has distinct header and descriptor layouts but similar fixed-width record
semantics.

Implementing one complete parser module per named version would duplicate shared
logic and allow the variants to drift. A single parser containing raw version
checks would recreate the coupling removed in Phase 1.

## Decision

Represent a supported format as a profile that composes independent axes of
variation:

- header layout;
- field-descriptor layout;
- memo family;
- record metadata/layout;
- later, field capabilities and value/text policies.

Parsers dispatch on profile-selected layouts or families, never on scattered raw
version-byte checks. Keep shared logic shared and split concrete modules only when
algorithms materially differ.

During Phase 2:

1. Introduce `DBF.Schema` to own descriptor parsing, schema validation, duplicate
   name policy, and compilation of record offsets. `DBF.Field` remains metadata
   for one field.
2. Implement dBASE III and dBASE IV memo algorithms in separate internal modules,
   `DBF.Memo.DBT3` and `DBF.Memo.DBT4`, behind a small `DBF.Memo` facade.
3. Keep the two currently small header-layout clauses together until a third
   layout or growing variant-specific rules justify separate modules.
4. Keep record decoding profile-aware through compiled schema metadata. Do not
   add version checks to `DBF.Record`.
5. Defer separate value-decoder modules until Phase 3 defines blank, null,
   invalid, binary, numeric, and text semantics.

During Phase 3, profiles also declare the evidenced field-kind capabilities for
their record layout. Schema compilation turns those capabilities into value
decoders. A field kind absent from the selected profile remains unsupported even
if another planned format uses the same one-byte type code; this prevents legacy
profiles from accidentally invoking unverified Visual FoxPro binary semantics.

Do not define one large behavior for an entire format. These concerns vary
independently. Plain internal modules with explicit function contracts are
sufficient; strategy modules may be stored in profiles later if atom dispatch
becomes difficult to maintain.

## Consequences

Adding a variant composes existing layouts and introduces only genuinely new
algorithms. DBT III and DBT IV can evolve independently without duplicating table
parsing. Visual FoxPro support can add FPT and record metadata without pretending
that every part of its DBF layout is unique.

The codebase gains a few focused modules, but avoids both version-oriented parser
copies and one monolithic conditional parser. The same profiles and compiled
schema metadata can later be reused by a separate writer without making the
reader resource mutable.
