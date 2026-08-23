# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## UNRELEASED

### Changed

- Various architectual changes in the background.

## [0.2.0] - 2026-08-22

### Added

- `DBF.with_open/2,3` for callback-scoped reads with automatic resource cleanup.
- An opt-in `numeric: :exact` policy that returns integers for scale-zero numeric fields and `Decimal` values for positive scales while preserving floats by default.
- Explicit `encoding` and `encoding_errors` options with built-in Windows-1251/1252 decoding and strict, replacement, or raw-byte handling.
- Documented evidence-based support levels for the available DBF variants.
- Verified fixture-backed FoxBase and dBASE III support, including complete zipcode CSV comparison and representative DBT record oracles.

### Changed

- Field decoder selection is now compiled from profile capabilities with schema metadata, keeping textual and binary representations distinct before value decoding.
- The minimum supported Elixir version is now 1.15.
- The OTP application and Hex package names were corrected to `dbf_ex`.

### Fixed

- Opening now validates options before file access and returns contextual errors for malformed or truncated structures and missing required memos.
- Table and memo resources are acquired transactionally, cleaned up after failed opens, and closed idempotently.
- Corrected public type specifications for database errors, memo handles, and memo-file opening results.
- Duplicate decoded field names now fail schema parsing instead of silently overwriting record values.
- Legacy blank values now have documented per-type results; date, logical, float, and numeric parsing no longer uses exceptions for ordinary invalid input, and numeric suffix junk is no longer accepted as a partial value.
- Field names, character values, and textual DBT memos now use one language-driver-aware text policy while binary and structural bytes remain untouched.
- Legacy profiles no longer accidentally decode unsupported Visual FoxPro integer, currency, variable-width, or binary field kinds.
- FoxBase exact numerics now preserve decimal values when its compact descriptors omit scale metadata.
- Record access now consistently rejects invalid indexes and returns contextual errors for short reads, malformed values, and unknown record markers; enumeration stops after emitting a record error.
- dBASE III DBT memos now support multi-block values and reject malformed pointers, inconsistent headers, out-of-range blocks, and missing terminators.
- dBASE IV DBT memos now honor declared block sizes and total lengths, support multi-block values, recognize field terminators, and reject invalid signatures, pointers, and truncated blocks.
- Required memo companions now reject empty, truncated, and detectably mismatched DBT files during opening, including explicitly supplied paths.

## [0.1.0] - 2024-03-27

First release.
