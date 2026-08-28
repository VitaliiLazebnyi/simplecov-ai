# simplecov-ai

A custom `SimpleCov::Formatter` designed explicitly for consumption by Large Language Models (LLMs) and autonomous engineering agents.

Standard coverage reporters generate massive HTML files or exhaustive JSON/console outputs detailing every line number. This overwhelms strict LLM token constraints and relies on highly volatile line numbers. `simplecov-ai` solves this by generating a concise, structurally optimized **Markdown document** containing only the exact missing semantic coverage blocks.

## Why use simplecov-ai?

- **Semantic Resolution:** Instead of volatile line numbers, missing coverage is resolved via Abstract Syntax Tree (AST) mapping into immutable semantic groupings (e.g., Class, Module, Instance Method).
- **Maximum Token Conservation:** Fully covered files are completely omitted. If the report exceeds size limits, it safely truncates the output prioritizing the lowest-coverage files.
- **Actionable Delta Directives:** Missing branches and lines are mapped directly to method names, letting the AI instantly search the code and write targeted specs.
- **Directive Auditing:** Explicitly reports `:nocov:` bypasses, ensuring artificial metric inflation is completely transparent to the reviewing AI.

## Installation

Add this line to your application's `Gemfile` strictly in the `test` group:

```ruby
group :test do
  gem 'simplecov'
  gem 'simplecov-ai', require: false
end
```

## Usage & Configuration

Require and configure the formatter in your test helper (`spec_helper.rb` or `test_helper.rb`) after requiring `simplecov`:

```ruby
require 'simplecov'
require 'simplecov-ai'

# Optional Configuration (defaults shown below):
SimpleCov::Formatter::AIFormatter.configure do |config|
  config.report_path = 'coverage/ai_report.md'      # Output location
  config.max_file_size_kb = 50                      # Maximum size (Token Ceiling)
  config.max_snippet_lines = 5                      # AST context truncation limit
  config.output_to_console = false                  # Echo digest to STDOUT
  config.granularity = :fine                        # :fine (statements) or :coarse (methods)
  config.include_bypasses = true                    # Audit `:nocov:` ignores
end

SimpleCov.start do
  # Combine with your existing formatters
  SimpleCov.formatters = SimpleCov::Formatter::MultiFormatter.new([
    SimpleCov::Formatter::HTMLFormatter,
    SimpleCov::Formatter::AIFormatter
  ])
end
```

## Example Output

The output is written to `coverage/ai_report.md` (or your configured path), perfect for providing directly as context to an LLM:

```md
# AI Coverage Digest
**Status:** FAILED
**Global Line Coverage:** 92.5%
**Global Branch Coverage:** 88.0%
**Generated At:** 2026-04-21T23:40:44+09:00 (Local Timezone)

## Coverage Deficits

### `lib/my_gem/client.rb`
- `MyGem::Client#initialize`
  - **Line Deficit:** [L4] `@token = nil`
- `MyGem::Client#authenticate!`
  - **Branch Deficit:** [L12] Missing coverage for `else` branch: `raise ExpiredTokenError`

### `lib/my_gem/parser/processor.rb`
- `MyGem::Parser::Processor.parse_stream`
  - **Branch Deficit:** [L8] Missing coverage for `then` branch: `break if stream.closed?`

## Ignored Coverage Bypasses

### `lib/my_gem/legacy_handler.rb`
- `MyGem::LegacyHandler#obsolete_action`
  - **Bypass Present:** Coverage explicitly ignored via `:nocov:`.
```

Each deficit is tagged with its source line(s) (`[L<n>]`) and the exact code snippet, so an
agent can locate the gap without depending on the surrounding line numbers. When branch coverage
is not enabled for the run, the header reports `N/A` for **Global Branch Coverage** rather than a
misleading `100%`.

## Error Handling

Coverage reporting is best-effort and never aborts a passing test run. When the AST parser cannot
process a file, that file degrades gracefully to raw line numbers (marked with an `AST Parsing
Failed` notice) instead of semantic groupings; column enrichment that a given SimpleCov version
does not support falls back to full-line snippets. Report generation is resilient to unreadable
or non-UTF-8 source files, emitting the report without the affected snippets rather than raising.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
