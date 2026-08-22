# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Credo and Dialyxir development tooling, with a `mix precommit` alias for compilation, formatting, tests, static analysis, and linting.
- A pre-push configuration for pre-commit.
- GitHub Actions CI for tests, formatting, Credo, and Dialyzer.
- Erlang/OTP and Elixir version pinning through `.tool-versions`.

### Changed

- The minimum supported Elixir version is now 1.18.
- ExDoc was updated to the 0.40 release series.
- The OTP application and Hex package names were corrected to `dbf_ex`.

### Fixed

- Corrected public type specifications for database errors, memo handles, and memo-file opening results.

## [0.1.0] - 2024-03-27

First release.
