# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.11.0] - 2026-08-29

### Fixed

- **SimpleCov 1.x compatibility.** Branch column enrichment no longer depends on the private
  `SimpleCov::SourceFile#restore_ruby_data_structure` helper removed in SimpleCov 1.0, and the
  file-level branch percentage uses the non-deprecated `covered_percent(:branch)` on
  SimpleCov >= 1.0, eliminating the per-run deprecation warning.
- Sub-line branch snippets (for example only the `:neg` arm of a ternary) survive SimpleCov's
  default result merging on 1.x: branch descriptors read back from `.resultset.json` are decoded
  with SimpleCov's own `SimpleCov::SourceFile::RubyDataParser` (the private
  `restore_ruby_data_structure` on 0.x), column offsets are matched by descriptor rather than by
  position and sliced by byte offset for multibyte source, and SimpleCov's `Branch` objects are
  never mutated.
- The report header no longer claims `100%` branch coverage when branch coverage was not
  enabled; it reports `N/A` instead, and the `Status` line accounts for every measured criterion
  so a report cannot show `PASSED` while listing deficits.
- Header percentages are floored to one decimal: a run at 99.96% reads `99.9%`, never `100.0%`
  beside a `FAILED` status.
- The bypass audit reports exactly what SimpleCov skipped, derived from SimpleCov's own skipped
  lines and branches instead of a second directive scan: `# :nocov:` pairs (including a custom
  `nocov_token`), inline `# simplecov:disable` comments and `# simplecov:disable line` /
  `# simplecov:disable branch` regions, while directives inside heredocs and directives the
  installed SimpleCov does not implement (`simplecov:disable` before 1.0) are not reported.
  Each entry quotes the directive comment itself as the reason, and an unmatched `# :nocov:`
  extends to the end of the file as it does in SimpleCov.
- Every resolved file starts with a `main` node (type `Root Script Scope`) spanning the whole
  file, so missed top-level lines and branches are reported under `main` instead of `Line N` /
  `Lines N-M` headings, and a bypass region wrapping only top-level code is listed instead of
  being dropped.
- Constant assignments without a block value (`MAJOR, MINOR = …`, `DEFAULT ||= …`) no longer
  crash AST resolution, which previously demoted the whole file to raw line numbers.
- More constructs resolve to precise names: `Module.new do … end` constants (`Mixin#helper`),
  `define_method` / `define_singleton_method` blocks with a literal name (`Klass#name`,
  `Klass.name`), numbered-parameter (`_1`) and Ruby 3.4 `it` blocks, and `class << obj` singleton
  classes opened on a local variable, instance variable or constant (`obj.name`, `@ivar.name`,
  `Foo::Bar.name`).
- Methods inside `class << self` are named as singleton methods; compact class definitions
  (`class Foo::Bar`) retain their namespace; foreign singleton receivers (`def String.x`) and
  nested `def`s are attributed correctly.
- Two same-named methods redefined in one file no longer merge into a single deficit group, and
  groups are ordered deterministically (start line, wider span first, then name).
- `max_file_size_kb` is a hard ceiling: the written file never exceeds it. Both the deficit and
  the bypass section stop at semantic-node granularity, and a single closing notice states how
  many deficit files and bypass files were omitted or cut short. Previously the limit was only
  checked after whole deficit files were written and the bypass section was not budgeted at all.
- The enclosing arm of an `elsif` chain (the `else` arm spanning the inner `elsif`) is quoted as
  its first source line followed by `...` instead of repeating every inner arm.
- Sources are read as bytes and decoded per their `# encoding:` magic comment or byte-order mark,
  so a Shift_JIS file resolves; string literals whose escapes are invalid in UTF-8
  (`"\xf0-\xff"`) are accepted as MRI accepts them; stray non-UTF-8 bytes in comments no longer
  discard the file's structure; report generation still never raises
  `Encoding::CompatibilityError`.
- Parser diagnostics never reach STDERR: the `parser/current is loading parser/rubyXY …` warning
  printed at load time is gone, and syntax warnings for the files being resolved are muted.
- The source of a file is read once, through the copy SimpleCov already loaded
  (`SourceFile#src`), instead of being re-read from disk for snippets and bypass reasons.
- Without an explicit `report_path` the digest is written to `ai_report.md` inside
  `SimpleCov.coverage_path`, so a custom `coverage_dir` is honoured. An explicit relative
  `report_path` still resolves against `SimpleCov.root`, independent of the working directory
  at exit.
- `output_to_console` echoes the full digest to STDOUT, matching the documented behaviour.
- Corrupt coverage data no longer aborts the report. When SimpleCov cannot decode a file's branch
  data (its `eval`-based decoder on SimpleCov < 1.0 raises `SyntaxError`, `RubyDataParser` on
  >= 1.0 raises `ArgumentError`), that file gets a single error entry, the header figures that
  depend on it read `N/A (coverage data could not be decoded)`, the status is `FAILED`, and every
  other file is reported normally.
- Runs on SimpleCov >= 1.0 that do not enable line coverage report
  `N/A (line coverage not enabled)` instead of failing.
- A `def` nested inside a method body within `class << self` is named as a singleton method
  (`Klass.name`), matching what Ruby defines.
- Whether a file has deficits is decided from SimpleCov's own missed lines, branches and methods
  rather than from rounded percentages.

### Changed

- The `simplecov` runtime dependency is bounded to `>= 0.18, < 2.0`.
- Parsing prefers Prism's `parser`-compatible translation on Ruby >= 3.3 (the exact grammar of
  the running Ruby, roughly twice as fast) when Prism >= 1.2 and `parser` >= 3.3.7.2 are
  installed; otherwise the `parser` gem grammar matching the running Ruby is loaded
  (`parser/current`, muted, as a last resort). Ruby 2.7–3.2 always use the `parser` gem.
- The truncation notice now reads `The report reached the maximum token constraint (N kB) and
  was truncated: X deficit file(s) and Y bypass file(s) omitted or cut short. …` and closes the
  report after the bypass section.
- Bypass entries quote the directive comment verbatim, for example `` Coverage explicitly
  ignored via `# :nocov:`. `` (previously `:nocov:`).
- Bypass auditing skips AST parsing for files SimpleCov skipped nothing in.
- Occurrence disambiguation for repeated snippets is indexed per node (linear) rather than
  re-scanning the node span for every deficit.

### Added

- SimpleCov >= 1.0 method coverage (`enable_coverage :method`): the header gains a
  `**Global Method Coverage:**` line (only when methods were measured), the status and the
  fully-covered check account for it, and every never-invoked method is listed as
  ``**Method Deficit:** [L28-31] `Sample::Calc#never_called` never invoked`` under its node.
- The formatter prints `AI coverage digest written to <path>` on STDOUT after writing the
  report (or the digest itself when `output_to_console` is set).
- Configuration attributes are validated on assignment: a value of the wrong type raises
  `TypeError` at the point of assignment (including `output_to_console=` and
  `include_bypasses=`, which now reject non-booleans), and out-of-range values (non-positive
  sizes, unknown granularity, a blank `report_path` or one containing a NUL byte) raise
  `ArgumentError` immediately rather than failing deep in coverage processing.
- `SimpleCov::Formatter::AIFormatter.reset_configuration!` for test isolation.

### Security

- Every snippet, node name, file path, branch type and bypass reason is rendered as a CommonMark
  code span whose backtick fence is longer than any backtick run in the content, so a backtick in
  source text or in a directive comment (a `# simplecov:disable` comment carrying Markdown,
  for instance) cannot close the span early and inject Markdown structure into the digest.
  Snippets are now quoted verbatim instead of having their backticks replaced.
- Gem signing is opt-in via `SIMPLECOV_AI_SIGN`. When set, the private key must exist and must
  match `certs/simplecov-ai-public_cert.pem` or the build fails loudly; when unset, the gem is
  built unsigned even if a `~/.gem/gem-private_key.pem` belonging to another certificate is
  present. The release workflow sets the variable only when the `GEM_PRIVATE_KEY` secret exists
  and verifies that a requested signature is present in the built gem.
- Development dependencies updated; `json` moves to 2.21.2 (CVE-2026-71847).

### Internal (development)

- Tapioca-generated gem RBIs (`sorbet/rbi/gems/`) replace the hidden-definitions RBI, and
  `srb tc --typed strong` passes on current Sorbet.
- `Gemfile.lock` is committed (resolved on Ruby 4.0) for the single-version gates; the CI test
  matrix resolves dependencies per Ruby. The Sorbet toolchain moved to the `Gemfile` behind an
  MRI/non-Windows guard so the bundle installs on Windows, JRuby and TruffleRuby.
- `bundle exec rake` runs every gate (spec, rubocop, typecheck, docs, audit, build);
  `bin/setup`, `bin/check-ruby` (any Ruby in Docker), `rake quality` (reek, flay, flog,
  debride) and `rake rbi` are added.
- CI adds actionlint, zizmor, markdownlint, typos, bundler-audit, a strict gem build with a
  clean-`GEM_HOME` install smoke test, Semgrep, Gitleaks, CodeQL, the OpenSSF Scorecard, a
  SimpleCov 0.18 / 0.21 / 0.22 / 1.0 / 1.1 compatibility matrix and non-blocking Windows, JRuby
  and TruffleRuby runs; all actions are SHA-pinned and updated by Dependabot.
- Releases verify that `lib/simplecov-ai/version.rb` matches the tag and refuse to publish
  without a `CHANGELOG.md` heading for it.
- The test suite drives the formatter with real SimpleCov objects, with sorbet-runtime signature
  checks enabled, across SimpleCov 0.18–1.1.
- Mutation testing with mutant is a blocking gate (`rake mutant`; 100% of mutations killed). The
  suite additionally runs an end-to-end child-process spec through SimpleCov's real result-merging
  path, a resolver run over the sources of every gem in the bundle, seeded property and fuzz
  specs, treats Ruby warnings emitted from `lib/` as failures (`RUBYOPT=-w`), and enforces 100%
  method coverage on SimpleCov >= 1.0.

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

[Unreleased]: https://github.com/VitaliiLazebnyi/simplecov-ai/compare/v0.11.0...HEAD
[0.11.0]: https://github.com/VitaliiLazebnyi/simplecov-ai/compare/v0.10.6...v0.11.0
[0.10.6]: https://github.com/VitaliiLazebnyi/simplecov-ai/compare/v0.10.5...v0.10.6
[0.10.5]: https://github.com/VitaliiLazebnyi/simplecov-ai/compare/v0.10.4...v0.10.5
[0.10.4]: https://github.com/VitaliiLazebnyi/simplecov-ai/compare/v0.10.3...v0.10.4
[0.10.3]: https://github.com/VitaliiLazebnyi/simplecov-ai/compare/v0.10.2...v0.10.3
[0.10.2]: https://github.com/VitaliiLazebnyi/simplecov-ai/compare/v0.10.1...v0.10.2
[0.10.1]: https://github.com/VitaliiLazebnyi/simplecov-ai/compare/v0.10.0...v0.10.1
[0.10.0]: https://github.com/VitaliiLazebnyi/simplecov-ai/releases/tag/v0.10.0
