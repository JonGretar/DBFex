# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `DBF.with_open/2,3` for callback-scoped reads with automatic resource cleanup.
- Documented evidence-based support levels for the available DBF variants.

### Changed

- Field decoder selection is now compiled with schema metadata, keeping textual and binary representations distinct before value decoding.
- The minimum supported Elixir version is now 1.18.
- The OTP application and Hex package names were corrected to `dbf_ex`.

### Fixed

- Opening now validates options before file access and returns contextual errors for malformed or truncated structures and missing required memos.
- Table and memo resources are acquired transactionally, cleaned up after failed opens, and closed idempotently.
- Corrected public type specifications for database errors, memo handles, and memo-file opening results.
- Duplicate decoded field names now fail schema parsing instead of silently overwriting record values.
- Legacy blank values now have documented per-type results; date, logical, float, and numeric parsing no longer uses exceptions for ordinary invalid input, and numeric suffix junk is no longer accepted as a partial value.
- Record access now consistently rejects invalid indexes and returns contextual errors for short reads, malformed values, and unknown record markers; enumeration stops after emitting a record error.
- dBASE III DBT memos now support multi-block values and reject malformed pointers, inconsistent headers, out-of-range blocks, and missing terminators.
- dBASE IV DBT memos now honor declared block sizes and total lengths, support multi-block values, recognize field terminators, and reject invalid signatures, pointers, and truncated blocks.
- Required memo companions now reject empty, truncated, and detectably mismatched DBT files during opening, including explicitly supplied paths.

## [0.1.0] - 2024-03-27

First release.
