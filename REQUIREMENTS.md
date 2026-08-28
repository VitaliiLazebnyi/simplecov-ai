# SimpleCov AI Formatter

## 1. Goal & Vision

The goal of this library is to provide a custom `SimpleCov::Formatter` designed explicitly for consumption by Large Language Models (LLMs) and autonomous engineering agents. Standard coverage reporters generate massive HTML files or exhaustive JSON/console outputs detailing every line number, which overwhelms the strict token constraints of LLMs and relies on volatile reference points.

This gem will consume standard SimpleCov result sets and output a highly concise, structurally optimized **Markdown document** containing only the exact missing semantic coverage blocks, formatted to minimize token use and maximize actionable context.

## 2. Why This is the "Best" Approach for AI

Generating reports via conventional coverage tools relies heavily on line numbers (e.g., identifying deficits via transient line coordinates). This directly conflicts with secure and modern AI development standards, explicitly the **Strict Ban on Volatile Line Numbers**. Line numbers rapidly shift during code refactoring, breaking the AI's internal maps of the codebase.

This gem provides the best approach because it introduces **Semantic Resolution**:

1. **Abstract Syntax Tree (AST) Mapping:** Instead of outputting line numbers, the tool will parse the raw Ruby source files holding the missing coverage (via native AST tools like `parser` and `ast`). It resolves the missing lines back to their stable syntactic enclosures (e.g., `MyGem::Client#connect` or `MyGem::Runner.execute`).
2. **Maximum Token Conservation:** Codebases with thousands of lines but high coverage will not bloat the prompt. Fully covered files are completely omitted from the detailed digest, and source code snippets are entirely stripped.
3. **Actionable Delta Directives:** By seeing a missing branch mapped directly to a method name, the AI can instantly search the code and write a spec targeting that exact logical boundary.

## 3. Specifications & Constraints

**Sub-Domain Identifier:** `SCAI` (SimpleCov Markdown)

### 3.1. Functional Behavior

- **SCAI-REQ-001 (Formatter Hook):** The library MUST natively integrate with SimpleCov via `SimpleCov.formatter = SimpleCov::Formatter::AIFormatter`.
- **SCAI-REQ-002 (Artifact Generation):** Upon test suite exit, the library MUST output a singular data document (default path: `coverage/ai_report.md`). If configured to do so, the formatter MUST additionally safely echo the finalized digest string directly to standard output (`STDOUT`) for immediate human readability in a terminal.
- **SCAI-REQ-003 (Pruning Fully Covered Files):** The library MUST securely drop all files achieving 100% line and branch coverage from the report's detailed breakdown to aggressively conserve LLM token context. If the entire test suite achieves 100% coverage (i.e., there are zero deficits), the report MUST completely omit the `## Coverage Deficits` section, resulting in only the summary header (and bypasses, if any) to further reduce token usage and explicitly signify a perfect run.
- **SCAI-REQ-004 (Semantic Resolution via AST):** The library MUST parse the source of under-covered files (using standard parsers like `parser`) to cross-reference `SimpleCov`'s exact coordinates (including line strings and column bounds) with the AST structure. Missing coverage MUST be translated by traversing up the AST to resolve the deficit into immutable semantic groupings (e.g., Class, Module, Instance Method, Singleton Method, or Root Script Scope).
- **SCAI-REQ-005 (Coverage Type Segmentation):** The report MUST distinguish clearly between `Line Deficits` (unexecuted statements) and `Branch Deficits` (unexecuted conditionals) to clarify the scope of the required test.
- **SCAI-REQ-012 (Token Ceiling / Truncation):** To prevent prompt bloat, if the generated report exceeds a predefined file size limit (calculated in strict Metric units, e.g., 50 kB), the formatter MUST prioritize the lowest-coverage files first and explicitly state the truncation in the report.
- **SCAI-REQ-013 (Directive Auditing):** The library MUST parse source file comments to identify the presence of SimpleCov exclusion directives (e.g., `:nocov:`). The formatter MUST explicitly report the semantic envelope (e.g., Method or Class) encasing any such bypass in the final markdown document. This ensures that any artificial inflation of coverage metrics is fully transparent to the auditing AI.
- **SCAI-REQ-019 (Parallel Result Merging):** Modern automated infrastructures execute tests in parallel (e.g., via `parallel_tests`), generating partial coverage sets. SimpleCov itself merges these partial result sets (per its `merge_timeout`) and invokes the formatter once with the aggregated `SimpleCov::Result`. The formatter MUST therefore process whatever `Result` it is handed transparently, without assuming a single-process run — which it does, as `#format` derives everything from the passed `Result` and imposes no run-count assumptions.

### 3.2. Formatter Implementation & UX

- **SCAI-REQ-006 (Summary Header):** The markdown output MUST begin with a consolidated telemetry header documenting overall line percentage, branch percentage, generation timestamp, and PASS/FAIL state. While internal temporal logic MUST be mathematically UTC, this markdown report acts as a presentation layer and MUST dynamically convert and format the timestamp to the user's preferred local timezone.
- **SCAI-REQ-007 (Context Window Preservation):** The formatter MUST NOT print surrounding code blocks or contextual snippets around the deficit. It is strictly limited to printing the exact, localized text of the isolated AST node responsible for the deficit (e.g., the specific unexecuted conditional string `break if stream.closed?`) to maximize token efficiency. If the isolated AST node text exceeds a predefined line limit (e.g., `max_snippet_lines` config, defaulting to 5 lines), the formatter MUST safely truncate the snippet and append a truncation indicator (`...`) to prevent prompt bloat. If multiple identical textual AST nodes exist within the same semantic block, the formatter MUST disambiguate them using an occurrence index (e.g., `(Occurrence 2 of 3)`) rather than volatile line numbers.
- **SCAI-REQ-014 (Deterministic Output Sorting & Token Deduplication):** To ensure output consistency and prioritize the most critical work, the detailed file reports MUST be strictly sorted. The primary sort index MUST be the **Coverage Percentage (Ascending order)** so that the worst-covered files appear sequentially at the top. The secondary tie-breaking sort MUST be the **File Path (Alphabetical order)**. Inside individual file blocks, the AST semantic nodes MUST be grouped and sorted chronologically/vertically as they naturally appear top-down within the source file. To strictly enforce maximum token conservation, multiple missed lines or branches mapped to the exact same semantic node MUST be grouped under a single node heading rather than repeating the semantic boundaries.

### 3.3. Internal Gem Standards

- **SCAI-REQ-008 (Maximum Rigor Test Coverage & Anti-Coverage Paradox):** The gem's test suite MUST rigorously establish and maintain 100% deterministic line and branch coverage. However, achieving 100% execution coverage is meaningless if assertions are weak (the "Coverage Paradox"). Tests MUST NOT be tautological. All mocks MUST strictly adhere to the exact real-world interfaces and exceptions of their target components (e.g., matching specific native exception classes like `Parser::SyntaxError` instead of generic `StandardError`). Furthermore, structural testing MUST employ deep, nested data fixtures rather than simple flat lists to properly validate boundary logic. Textual formatting MUST be validated using multi-line Regex matchers to enforce chronological order, strictly forbidding isolated string presence assertions (like `.to include()`). The use of coverage-dodging directives (e.g., `:nocov:`) is strictly forbidden by default. They are permitted ONLY when absolute compliance is technically impossible (e.g., genuinely untestable system crashes), and any such bypass MUST be immediately preceded by a comment explicitly justifying the architectural limitation. Any randomness or time-based execution must be explicitly mocked.
- **SCAI-REQ-009 (Strict Analytical Compliance):** The gem MUST implement maximum-rigor RuboCop static analysis checks. `rubocop:disable` directives are systematically banned unless mathematically impossible to avoid (e.g., flawed upstream library typings). Any permitted bypass MUST be immediately preceded by an inline comment explicitly justifying the architectural limitation.
- **SCAI-REQ-010 (Strict Type Safety):** The gem MUST utilize a static typing overlay (e.g., Sorbet with `# typed: strict` typing globally) to mathematically eliminate runtime type anomalies.
- **SCAI-REQ-011 (Graceful Degradation):** The system MUST contain processing failures at the file level rather than aborting the test run. If the AST parser encounters structurally unparsable Ruby code (e.g., a dynamically generated file), it MUST gracefully degrade: it records the file as a deficit using the raw SimpleCov line coordinates, explicitly denoting the parsing failure in the Markdown output, before safely continuing to process the remaining valid files. Missing branch-column telemetry and unreadable source files degrade the same way (see §4.5).
- **SCAI-REQ-020 (AST Caching & Performance):** To eliminate redundant file system I/O and overhead, the formatter MUST maintain an internal AST cache memory buffer mapping file paths to resolved syntax trees. This ensures a file is fully parsed mathematically exactly once, even when subjected to multiple traversals for deficit detection and bypass auditing.
- **SCAI-REQ-021 (Self-Documenting Mandate):** Code MUST be immediately readable by LLMs and human maintainers without relying heavily on inline comments. The code's intent MUST be derived entirely from expressive, domain-specific variable, method, and parameter naming. Generic identifiers (e.g., `result`, `group`, `f`, `n`) are strictly forbidden.
- **SCAI-REQ-022 (Zero-Bypass Formatting Strictness):** Any modifications that increase code verbosity for the sake of clarity (resulting in longer lines or larger classes) MUST be structurally accommodated. Developers MUST extract methods and reorganize logic to naturally pass all strict RuboCop limits without ever resorting to `# rubocop:disable` or inline `rescue` modifiers.

### 3.4. System Prerequisites & Dependencies

- **SCAI-REQ-015 (Ruby Version Constraint):** The gem MUST enforce a minimum Ruby version of `>= 2.7.0` and is tested across Ruby 2.7 through 4.0. AST parsing standardizes on the `whitequark/parser` gem rather than `prism` so a single, well-supported grammar path covers the entire version range (including 2.7, which predates `prism`).
- **SCAI-REQ-016 (SimpleCov Version Constraint):** The gem declares a `simplecov` dependency of `>= 0.18, < 2.0`. The `0.18` floor is API-accurate — it is the first release exposing the internal Branch Coverage telemetry required by `SCAI-REQ-005` — though the *effective installable* floor on Ruby `>= 3.0` is higher, because Bundler resolves later 0.x/1.x releases there; on Ruby 2.7 the 0.x line resolves. The `< 2.0` ceiling bounds the range across which branch enrichment has been verified.

## 4. Usage & Configuration

This section outlines integration, configuration, and the expected developer-side workflow.

### 4.1. Installation

First, the library must be mapped in the project dependencies, strictly constrained to the testing environments to prevent production bloat:

```ruby
# Gemfile
group :test do
  gem 'simplecov'
  gem 'simplecov-ai', require: false
end
```

### 4.2. Integration & Configuration

To utilize the tool, it must be explicitly required subsequent to loading SimpleCov. The developer can also optionally override internal file size constraints and custom paths if the default `coverage/ai_report.md` does not fit their architecture.

```ruby
# spec_helper.rb or test_helper.rb
require 'simplecov'
require 'simplecov-ai'

# Optional: Override default behaviors and output data.
# All configuration parameters are initialized with strictly deterministic default values:
SimpleCov::Formatter::AIFormatter.configure do |config|
  # Output Targeting & File Constraints
  config.report_path = 'coverage/custom_digest.md'      # Default: 'coverage/ai_report.md'
  config.max_file_size_kb = 100                         # Default: 50
  config.max_snippet_lines = 5                          # Default: 5. Truncates long AST localized text.
  config.output_to_console = true                       # Default: false. Prints the final digest to STDOUT.

  # Structural Formats & Granularity
  config.granularity = :fine            # Default: :fine. Options: :fine (statements) or :coarse (methods)

  # Fine-grained control over what data is stored in the digest:
  config.include_bypasses = true        # Default: true. Audits explicit :nocov: ignores.
end

SimpleCov.start do
  # Standard SimpleCov filters
  add_filter '/spec/'
  add_filter '/config/'

  # Formatter Configuration
  SimpleCov.formatters = SimpleCov::Formatter::MultiFormatter.new([
    SimpleCov::Formatter::HTMLFormatter,
    SimpleCov::Formatter::AIFormatter
  ])
end
```

### 4.3. Developer Workflow & Result Generation

The execution lifecycle remains entirely transparent from the end-user's perspective:

1. **Execution:** The developer or CI agent executes the test suite exactly as usual (e.g., `bundle exec rspec`).
2. **Collection:** `SimpleCov` tracks the executed Ruby trace points.
3. **AST Resolution:** Upon exit, the AI formatter hooks into the lifecycle, ingests the raw target coordinates, maps the deficits to their immutable AST boundaries, and prunes 100%-covered files.
4. **Persistence:** The formatter parses and formats the output, truncating early if `max_file_size_kb` is hit to protect token ceilings.

### 4.4. CI/CD & Artifact Retrieval

The formatter strictly writes the resulting digest to the predictable path (e.g., `coverage/ai_report.md`).

In an automated CI/CD pipeline, the engineer only needs to ensure the `coverage/` directory is exported as an artifact. A downstream autonomous agent or LLM reviewer can simply `cat coverage/ai_report.md` directly in the pipeline to immediately review the exact unexecuted classes, methods, or logical branches, bypassing manual review of massive HTML structures and eliminating token bloat.

### 4.5. Error Handling & Failure States

In adherence to `SCAI-REQ-011`, coverage reporting is best-effort and MUST NOT abort an otherwise-passing test run. Failures are contained at the file level:

1. **Broken Code Syntax:** If the AST parser cannot process an under-covered file, that file MUST degrade gracefully to raw line numbers, annotated in the Markdown with an `AST Parsing Failed` notice, while the remaining files are processed normally.
2. **Missing Telemetry:** If a given SimpleCov version does not expose the branch column data used for inline sub-snippets, the formatter MUST fall back to full-line snippets rather than raising.
3. **Unreadable Sources:** Files that cannot be read, or that contain non-UTF-8 bytes, MUST be reported without their snippets rather than interrupting artifact generation.

## 5. Example Output Reference

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

> **[WARNING] TRUNCATION NOTIFICATION:**
> The total coverage deficit report exceeded the maximum token constraint (50 kB). The report was truncated. The deficits detailed above represent the lowest-coverage (most critical) files. Please resolve these deficits to reveal the remaining uncovered files in subsequent test runs.
```

## [ARCHIVED]

The following requirements have been aggressively pruned to prevent feature bloat, respect the Single Responsibility Principle, and preserve the LLM context window.

- **[ARCHIVED] SCAI-REQ-017 (Format Flexibility):** Generating multiple structured output formats simultaneously (e.g., `JSON`, `YAML`) alongside Markdown. *Reason: Duplicates existing tools (like `simplecov-json`) and dilutes the library's fundamental goal of Markdown generation.*
- **[ARCHIVED] SCAI-REQ-018 (Test File Inference):** Inferring and rendering the expected spec file path directly in the header. *Reason: Relies on brittle, subjective heuristics that falter across diverse project architectures and test frameworks (RSpec/Minitest).*
- **[ARCHIVED] SCAI-REQ-014-b (Git Diff Prioritization):** Forcing files modified in the Git working tree to the top of the file sorting list. *Reason: Executes system calls to external version control interfaces which slows termination, creates environment coupling, and breaches the Single Responsibility Principle.*
