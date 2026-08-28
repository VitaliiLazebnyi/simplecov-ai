# simplecov-ai

A `SimpleCov::Formatter` that writes a compact Markdown digest of missing coverage for Large
Language Models (LLMs) and autonomous engineering agents.

Standard coverage reporters produce large HTML files or exhaustive JSON/console output keyed by
line numbers, which fills an LLM's context window with coordinates that shift on every edit.
`simplecov-ai` resolves each missed line and branch to its enclosing module, class or method
through the Ruby AST and emits only those semantic groups, each with the exact unexecuted
expression.

## What the digest contains

- **Semantic resolution.** Deficits are grouped under the innermost enclosing node:
  `Module::Class#method` for instance methods, `Module::Class.method` for singleton methods
  (`def self.x`, `class << self`), constants bound to `Struct.new`, `Class.new`, `Module.new` or
  `Data.define` blocks (`Point#distance`), `define_method` / `define_singleton_method` blocks with
  a literal name, and `class << obj` singleton classes opened on a variable or constant
  (`obj.name`, `@ivar.name`, `Foo::Bar.name`). Code outside any class or method belongs to
  `main`, the root scope of the file.
- **Exact snippets.** Each deficit carries its line(s) as `[L<n>]` or `[L<n>-<m>]` and the exact
  source text: a missed branch quotes only its own arm (the `:neg` of `x.positive? ? :pos : :neg`),
  the `else` arm that spans an `elsif` chain is cut to its first line plus `...`, and identical
  lines within one node are told apart with `(Occurrence N of M)`.
- **Token conservation.** Fully covered files are omitted, the `## Coverage Deficits` section
  disappears on a perfect run, and `max_file_size_kb` is a hard ceiling on the written file.
- **Bypass audit.** Every region SimpleCov skipped (`# :nocov:`, `# simplecov:disable`) is listed
  with the directive that caused it, so artificially inflated metrics stay visible to the reader.
- **Method coverage.** With SimpleCov >= 1.0 and `enable_coverage :method`, never-invoked methods
  are reported too.

## Requirements

- **Ruby** 2.7 through 4.0 (MRI). JRuby and TruffleRuby run the formatter but implement no branch
  coverage, so only line deficits are reported there and the header shows `N/A` for branches.
- **SimpleCov** `>= 0.18, < 2.0`. Branch coverage needs `enable_coverage :branch`. Method
  coverage and `# simplecov:disable` directives are SimpleCov 1.x features; on older releases they
  are neither measured nor reported.

## Installation

```ruby
group :test do
  gem 'simplecov'
  gem 'simplecov-ai', require: false
end
```

## Usage

Require the formatter after `simplecov` in your test helper and register it with SimpleCov:

```ruby
require 'simplecov'
require 'simplecov-ai'

SimpleCov.start do
  enable_coverage :branch
  skip '/spec/'         # SimpleCov >= 1.0; use `add_filter '/spec/'` on 0.x (1.x deprecates it)
end

SimpleCov.formatter = SimpleCov::Formatter::AIFormatter
# Alongside other formatters:
# SimpleCov.formatters = [SimpleCov::Formatter::HTMLFormatter, SimpleCov::Formatter::AIFormatter]
```

When the suite exits, the formatter writes the report and announces it on STDOUT:

```text
AI coverage digest written to /path/to/project/coverage/ai_report.md
```

### Configuration

All settings are optional; the defaults are shown:

```ruby
SimpleCov::Formatter::AIFormatter.configure do |config|
  config.report_path = 'coverage/ai_report.md' # default: ai_report.md inside SimpleCov's coverage_dir
  config.max_file_size_kb = 50                 # hard ceiling on the written file (metric kB)
  config.max_snippet_lines = 5                 # snippets longer than 5 x 80 characters end in `...`
  config.output_to_console = false             # true: print the digest to STDOUT instead of the notice
  config.granularity = :fine                   # :fine (every line/branch) or :coarse (one line per node)
  config.include_bypasses = true               # false: omit the "Ignored Coverage Bypasses" section
end
```

- `report_path` — unset, the digest goes to `ai_report.md` inside `SimpleCov.coverage_path`, so
  a custom `coverage_dir` is honoured (the reader reports this default as
  `coverage/ai_report.md`). An explicit absolute path is used as-is; an explicit relative path is
  resolved against `SimpleCov.root`, independent of the working directory at exit. Blank values
  and values containing a NUL byte are rejected.
- `max_file_size_kb`, `max_snippet_lines` — positive Integers.
- `granularity` — `:fine` or `:coarse`.
- `output_to_console`, `include_bypasses` — `true` or `false`.

Every setting is validated when it is assigned: a value of the wrong type raises `TypeError`
(the writers are typed with sorbet-runtime) and an out-of-range value raises `ArgumentError`
naming the setting, for example `granularity must be one of [:fine, :coarse], got :medium`.
`SimpleCov::Formatter::AIFormatter.reset_configuration!` discards the configuration so the next
access starts from the defaults (useful in test suites).

## Example output

Generated from a small sample project on Ruby 4.0 and SimpleCov 1.1.1, trimmed by one file and
one node that quotes a 300-character line:

```md
# AI Coverage Digest
**Status:** FAILED
**Global Line Coverage:** 69.3%
**Global Branch Coverage:** 38.4%
**Generated At:** 2026-08-28T06:05:29+00:00 (Local Timezone)
## Coverage Deficits

### `lib/sample/weird.rb`
- `Sample::Weird#dupes`
  - **Line Deficit:** [L11] `a += 1` (Occurrence 1 of 3).
  - **Line Deficit:** [L12] `a += 1` (Occurrence 2 of 3).
  - **Line Deficit:** [L13] `a += 1` (Occurrence 3 of 3).
  - **Line Deficit:** [L14] `a`

### `lib/sample/calc.rb`
- `Sample::Calc#sign`
  - **Branch Deficit:** [L7] Missing coverage for `else` branch: `:neg`
- `Sample::Calc#classify`
  - **Line Deficit:** [L13] `elsif n.odd?`
  - **Line Deficit:** [L14] `:odd`
  - **Line Deficit:** [L16] `:even`
  - **Branch Deficit:** [L13-17] Missing coverage for `else` branch: `elsif n.odd?...`
  - **Branch Deficit:** [L14] Missing coverage for `then` branch: `:odd`
  - **Branch Deficit:** [L16] Missing coverage for `else` branch: `:even`
- `Sample::Calc#bucket`
  - **Line Deficit:** [L23] `when 2 then :two`
  - **Line Deficit:** [L24] `else :many`
  - **Branch Deficit:** [L23] Missing coverage for `when` branch: `:two`
  - **Branch Deficit:** [L24] Missing coverage for `else` branch: `:many`
- `Sample::Calc#never_called`
  - **Line Deficit:** [L29] `@never = 1`
  - **Line Deficit:** [L30] `@never += 1`
- `Sample::Calc.unused_factory`
  - **Line Deficit:** [L55] `new.tap { |c| c.sign(1) }`
- `Sample::Point#origin?`
  - **Line Deficit:** [L66] `x.zero? && y.zero?`

### `lib/sample/boot.rb`
- `main`
  - **Branch Deficit:** [L9] Missing coverage for `then` branch: `true`

## Ignored Coverage Bypasses

### `lib/sample/boot.rb`
- `main`
  - **Bypass Present:** Coverage explicitly ignored via `# :nocov:`.

### `lib/sample/calc.rb`
- `Sample::Calc#legacy_skipped`
  - **Bypass Present:** Coverage explicitly ignored via `# :nocov:`.
- `Sample::Calc#inline_disabled`
  - **Bypass Present:** Coverage explicitly ignored via `# simplecov:disable`.
- `Sample::Calc#branch_scoped`
  - **Bypass Present:** Coverage explicitly ignored via `# simplecov:disable branch`.
```

Things to notice:

- Files are ordered by coverage, lowest first (path as the tie-break); nodes appear in source
  order.
- `main` is the root scope of `lib/sample/boot.rb`: the missed `then` arm belongs to a top-level
  statement (`SAMPLE_DEBUG = ENV['SAMPLE_DEBUG'] ? true : false`), and the `# :nocov:` region
  wraps only top-level code.
- `[L13-17] … elsif n.odd?...` is the `else` arm of the outer `if` in `classify`; it spans the
  whole `elsif` chain, so it is cut to its first line instead of repeating the inner arms.
- The `Status` is `PASSED` only when every measured criterion is at 100%, and percentages are
  floored to one decimal, so a run at 99.96% reads `99.9%`.

### Method coverage (SimpleCov >= 1.0)

With `enable_coverage :method` the header gains a method line, the status accounts for it, and
each never-invoked method is listed under its node before its line and branch deficits. From the
same sample:

```md
**Global Method Coverage:** 53.3%
```

```md
- `Sample::Calc#never_called`
  - **Method Deficit:** [L28-31] `Sample::Calc#never_called` never invoked
  - **Line Deficit:** [L29] `@never = 1`
  - **Line Deficit:** [L30] `@never += 1`
```

### Bypass audit

The `## Ignored Coverage Bypasses` section lists what SimpleCov actually skipped, attributed to
the outermost nodes a skipped region contains (or to the node enclosing it, `main` at worst), with
the directive comment quoted verbatim as the reason. Because it is derived from SimpleCov's own
skip verdicts rather than from a second scan of the comments:

- `# :nocov:` pairs (including a custom `nocov_token`), inline `# simplecov:disable` comments and
  `# simplecov:disable line` / `# simplecov:disable branch` regions are all reported;
- a directive inside a heredoc, which SimpleCov ignores, is not reported;
- on SimpleCov < 1.0, which does not implement `# simplecov:disable`, those lines stay ordinary
  deficits and only `# :nocov:` regions appear. The same sample on SimpleCov 0.22.0 lists
  `raise 'unreachable' # simplecov:disable` as a line deficit and a single bypass.

SimpleCov 1.x itself deprecates `# :nocov:` in favour of `# simplecov:disable` /
`# simplecov:enable`; both are audited.

### Size ceiling

`max_file_size_kb` bounds the written file. Both sections are filled lowest-coverage file first,
one semantic node at a time, until the next node would no longer fit; a single notice then closes
the report. With a 1 kB limit the sample above ends in:

```md
> **[WARNING] TRUNCATION NOTIFICATION:**
> The report reached the maximum token constraint (1 kB) and was truncated: 3 deficit file(s) and 2 bypass file(s) omitted or cut short. Lowest-coverage files are listed first; resolve the deficits above to reveal the remaining ones in subsequent test runs.
```

A file whose block was cut short counts towards those numbers. No notice is printed when
everything fits.

## Parser backend

Sources are parsed with Prism's `parser`-compatible translation on Ruby >= 3.3 when Prism >= 1.2
and `parser` >= 3.3.7.2 are installed (the exact grammar of the running Ruby, about twice as fast
as the `parser` gem); otherwise the `parser` gem's grammar for the running Ruby is used, with
`parser/current` as a muted last resort. Ruby 2.7 to 3.2 always use the `parser` gem. The
selection happens once at load time, and no parser diagnostic — including the
`parser/current is loading …` version warning — is ever written to STDERR.

## Error handling

Reporting is best-effort and never aborts a passing test run. A file the parser cannot process is
listed with its raw line numbers under an `AST Parsing Failed` notice while the other files are
resolved normally. Sources are read as bytes and decoded per their `# encoding:` magic comment or
byte-order mark, string literals whose escapes are invalid in UTF-8 (`"\xf0-\xff"`) are accepted
as MRI accepts them, and a file that cannot be read at all is reported without snippets. Branch
column data that a SimpleCov version does not provide degrades to full-line snippets. Snippets,
names, paths and directive comments are rendered as code spans that stay intact whatever
characters they contain (see `SECURITY.md`).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
