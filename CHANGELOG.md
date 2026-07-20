# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.11.0]

### Fixed

- **SimpleCov 1.x compatibility.** Branch column enrichment no longer depends on the private
  `SimpleCov::SourceFile#restore_ruby_data_structure` helper removed in SimpleCov 1.0; branch
  descriptors are now read from the native array form (with a fallback to the stringified form
  for SimpleCov < 1.0). Branch column offsets are matched by descriptor rather than by fragile
  positional zipping, and sliced by byte offset to stay correct for multibyte source.
- Branch coverage percentage now uses the non-deprecated `covered_percent(:branch)` API on
  SimpleCov >= 1.0, eliminating the per-run deprecation warning.
- The report header no longer claims `100%` branch coverage when branch coverage was not
  enabled; it reports `N/A` instead, and the `Status` line accounts for branch coverage so a
  report cannot show `PASSED` while listing branch deficits.
- `:nocov:` directives are now paired into regions (matching SimpleCov's semantics) and detected
  with an anchored pattern, fixing false positives on prose mentions and the regression where a
  paired region flagged the following, fully covered method. `# simplecov:disable` /
  `# simplecov:enable` block directives are now audited as well, and the captured directive text
  is emitted as the bypass reason.
- Methods inside `class << self` are now named as singleton methods; compact class definitions
  (`class Foo::Bar`) retain their namespace; foreign singleton receivers (`def String.x`) and
  nested `def`s are attributed correctly.
- Two same-named methods redefined in one file no longer merge into a single deficit group.
- `max_file_size_kb` is now enforced after each deficit file, so a single oversized file (or the
  last file in a set) triggers truncation.
- Reports containing non-UTF-8 source bytes no longer raise `Encoding::CompatibilityError`;
  snippets with backticks no longer break inline code spans.
- `output_to_console` now echoes the full digest to STDOUT, matching the documented behavior.
- The report is written to a path resolved against `SimpleCov.root`, independent of the process
  working directory at exit.

### Added

- Configuration attributes are validated on assignment: type mismatches are rejected via the
  writer signatures, and out-of-range values (non-positive sizes, unknown granularity) raise
  `ArgumentError` immediately rather than failing deep in coverage processing.
- `SimpleCov::Formatter::AIFormatter.reset_configuration!` for test isolation.

### Changed

- The `simplecov` runtime dependency is bounded to `>= 0.18, < 2.0`.
- Bypass auditing skips full AST parsing for files that contain no bypass directive.
- Occurrence disambiguation for repeated snippets is now indexed per node (linear) rather than
  re-scanning the node span for every deficit.
