# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.11.0] - unreleased

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

## [0.10.6] - 2026-05-21

### Fixed

- The global branch coverage percentage reports `100%` instead of `0%` when SimpleCov records
  zero (or no) branches, so a project without conditionals is no longer reported as failing
  branch coverage.

### Changed

- The gem's own test suite now enforces 100% line and branch coverage.

## [0.10.5] - 2026-05-20

### Added

- Branch deficits are enriched with SimpleCov's column offsets, so a missed branch quotes the
  exact inline expression (for example only the `else` arm) instead of the whole line, and each
  branch deficit is labelled with its line range and branch type
  (`[L12] Missing coverage for else branch: ...`).
- Fixture suites covering exhaustive branching shapes and metaprogramming constructs
  (`Struct.new`, `Class.new`, `Data.define`, `class << self`).

### Changed

- A file only counts as fully covered when both its line and its branch coverage are 100%, so
  files with missed branches are no longer omitted from the digest.
- Configuration defaults are exposed as `Configuration::DEFAULT_*` constants; the truncation
  notice and other shared strings moved to named constants.
- The gem's own quality bar now includes the RuboCop Sorbet/RSpec/Performance/ThreadSafety
  rule sets.

## [0.10.4] - 2026-04-25

### Fixed

- `:nocov:` bypasses are attributed to the innermost enclosing semantic node only, instead of to
  every enclosing module, class and method.
- Deficits are grouped by the innermost enclosing node (the most specific method rather than the
  outer class) and listed in source order.
- The minimum Ruby version is declared correctly as `>= 2.7.0`.

### Changed

- `Gemfile.lock` is no longer committed; each Ruby in the CI matrix resolves its own dependency
  set.
- `BUGS.md` documents the root-cause analyses behind the fixes in this release.

## [0.10.3] - 2026-04-24

### Added

- README documentation covering installation, configuration and example output.

### Fixed

- `granularity = :coarse` now emits a single summary line per semantic node instead of the
  per-line detail, as documented.
- Identical snippets within one semantic node are disambiguated with an
  `(Occurrence N of M)` marker.
- Removed the accidental self-dependency from the gemspec and the `parallel` version pin that
  had been added for Ruby 3.2 CI compatibility.

### Changed

- The Markdown builder was split into dedicated deficit, bypass, grouping and snippet
  components, and the code base moved to `srb tc --typed strong` with tapioca-managed RBIs.

## [0.10.2] - 2026-04-22

### Fixed

- Re-release of 0.10.1 with the packaging metadata corrected.

## [0.10.1] - 2026-04-22

### Fixed

- The `## Coverage Deficits` section is omitted entirely when every file is fully covered,
  instead of rendering an empty heading.
- Sorbet `typed: strong` compliance fixes in the Markdown builder.

## [0.10.0] - 2026-04-22

### Added

- Initial public release: a `SimpleCov::Formatter` that writes a token-efficient Markdown
  digest mapping missed lines and branches to their enclosing modules, classes and methods via
  the `parser` AST, with configurable `report_path`, `max_file_size_kb`, `max_snippet_lines`,
  `output_to_console`, `granularity` and `include_bypasses`, a truncation notice for oversized
  reports and an audit section listing `:nocov:` bypasses.
- Signed gem releases (public certificate in `certs/`).

[Unreleased]: https://github.com/VitaliiLazebnyi/simplecov-ai/compare/v0.10.6...HEAD
[0.11.0]: https://github.com/VitaliiLazebnyi/simplecov-ai/compare/v0.10.6...HEAD
[0.10.6]: https://github.com/VitaliiLazebnyi/simplecov-ai/compare/v0.10.5...v0.10.6
[0.10.5]: https://github.com/VitaliiLazebnyi/simplecov-ai/compare/v0.10.4...v0.10.5
[0.10.4]: https://github.com/VitaliiLazebnyi/simplecov-ai/compare/v0.10.3...v0.10.4
[0.10.3]: https://github.com/VitaliiLazebnyi/simplecov-ai/compare/v0.10.2...v0.10.3
[0.10.2]: https://github.com/VitaliiLazebnyi/simplecov-ai/compare/v0.10.1...v0.10.2
[0.10.1]: https://github.com/VitaliiLazebnyi/simplecov-ai/compare/v0.10.0...v0.10.1
[0.10.0]: https://github.com/VitaliiLazebnyi/simplecov-ai/releases/tag/v0.10.0
