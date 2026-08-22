# DBFex

DBFex is an Elixir library for reading dBASE/DBF files. It currently supports reading FoxBase, dBASE III, and dBASE IV variants, including DBT/FPT memo files. The public API lives in `DBF`; parsing is split across `DBF.Database`, `DBF.Field`, `DBF.Record`, and `DBF.Memo`.

## Development guidelines

- Preserve the public tagged-tuple API and `Enumerable` implementation unless a change explicitly requires breaking compatibility.
- Treat files under `test/dbf_files/` as fixtures; do not rewrite binary fixtures.
- Add regression tests using the smallest suitable fixture when changing a parser.
- The file DBF-Format.md includes notes about the file format, references about it and example projects. If you find valuable notes to jot down for future agents you can use that file.
- Use Jujutsu (`jj`) rather than Git for version-control operations.

## Changelog

Follows [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/).

- New work goes under `## [Unreleased]` with subsections (`### Added`, `### Fixed`, etc.)
- Generate a release **ONLY** when instructed to do so.
- On release: replace `## [Unreleased]` with `## [x.y.z] - YYYY-MM-DD` and bump `version:` in `mix.exs`. Create a tag with "v" prefix (`vx.y.z`) in the repository.

## Commands

```bash
mix test              # run tests
mix precommit         # compile, format check, tests, Dialyzer, and Credo
mix credo --strict    # lint
mix dialyzer          # static analysis
mix docs              # build ExDoc documentation
```

Install the pre-push checks with `pre-commit install --hook-type pre-push`.
