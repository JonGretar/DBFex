# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `DBF.with_open/2,3` for callback-scoped reads with automatic resource cleanup.
- Documented evidence-based support levels for the available DBF variants.

### Changed

- The minimum supported Elixir version is now 1.18.
- The OTP application and Hex package names were corrected to `dbf_ex`.

### Fixed

- Corrected public type specifications for database errors, memo handles, and memo-file opening results.

## [0.1.0] - 2024-03-27

First release.
