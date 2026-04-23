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
**Report File Size:** 1.2 kB

## Coverage Deficits

### `lib/my_gem/client.rb`
- `MyGem::Client#authenticate!`
  - **Branch Deficit:** Missing coverage for conditional evaluation handling `ExpiredTokenError`.
- `MyGem::Client#initialize`
  - **Line Deficit:** Variable initialization state uncovered.

### `lib/my_gem/parser/processor.rb`
- `MyGem::Parser::Processor.parse_stream`
  - **Branch Deficit:** Missing coverage for early-exit condition `break if stream.closed?` (Occurrence 1 of 2).

## Ignored Coverage Bypasses

### `lib/my_gem/legacy_handler.rb`
- `MyGem::LegacyHandler#obsolete_action`
  - **Bypass Present:** Contains `:nocov:` directive artificially ignoring coverage (Occurrence 1 of 1).
```

## Error Handling

Adhering to fail-fast principles, if the AST parser encounters structurally unparseable Ruby code or corrupt telemetry, it will gracefully degrade or explicitly fail. It will not silently ignore failures or emit corrupted artifacts.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
