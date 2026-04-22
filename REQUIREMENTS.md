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
- **SCAI-REQ-013 (Directive Auditing):** The library MUST parse source file comments to identify the presence of SimpleCov exclusion directives (e.g., `# :nocov:`). The formatter MUST explicitly report the semantic envelope (e.g., Method or Class) encasing any such bypass in the final markdown document. This ensures that any artificial inflation of coverage metrics is fully transparent to the auditing AI.
- **SCAI-REQ-019 (Parallel Result Merging):** Modern automated infrastructures execute tests in parallel (e.g., via `parallel_tests`), generating partial coverage sets. The formatter MUST possess explicit support for natively ingesting and deterministically processing merged `SimpleCov::Result` objects containing aggregated coverage data assembled at the culmination of a parallel test run.

### 3.2. Formatter Implementation & UX
- **SCAI-REQ-006 (Summary Header):** The markdown output MUST begin with a consolidated telemetry header documenting overall line percentage, branch percentage, generation timestamp, and PASS/FAIL state. While internal temporal logic MUST be mathematically UTC, this markdown report acts as a presentation layer and MUST dynamically convert and format the timestamp to the user's preferred local timezone.
- **SCAI-REQ-007 (Context Window Preservation):** The formatter MUST NOT print surrounding code blocks or contextual snippets around the deficit. It is strictly limited to printing the exact, localized text of the isolated AST node responsible for the deficit (e.g., the specific unexecuted conditional string `break if stream.closed?`) to maximize token efficiency. If the isolated AST node text exceeds a predefined line limit (e.g., `max_snippet_lines` config, defaulting to 5 lines), the formatter MUST safely truncate the snippet and append a truncation indicator (`...`) to prevent prompt bloat. If multiple identical textual AST nodes exist within the same semantic block, the formatter MUST disambiguate them using an occurrence index (e.g., `(Occurrence 2 of 3)`) rather than volatile line numbers.
- **SCAI-REQ-014 (Deterministic Output Sorting):** To ensure output consistency and prioritize the most critical work, the detailed file reports MUST be strictly sorted. The primary sort index MUST be the **Coverage Percentage (Ascending order)** so that the worst-covered files appear sequentially at the top. The secondary tie-breaking sort MUST be the **File Path (Alphabetical order)**. Inside individual file blocks, the AST semantic nodes MUST be grouped and sorted chronologically/vertically as they naturally appear top-down within the source file.

### 3.3. Internal Gem Standards
- **SCAI-REQ-008 (Maximum Rigor Test Coverage):** The gem's test suite MUST rigorously establish and maintain 100% deterministic line and branch coverage. Tests MUST NOT be tautological or lack meaningful assertions. The use of coverage-dodging directives (e.g., `# :nocov:`) is strictly forbidden by default. They are permitted ONLY when absolute compliance is technically impossible (e.g., genuinely untestable system crashes), and any such bypass MUST be immediately preceded by a comment explicitly justifying the architectural limitation. Any randomness or time-based execution must be explicitly mocked.
- **SCAI-REQ-009 (Strict Analytical Compliance):** The gem MUST implement maximum-rigor RuboCop static analysis checks. `rubocop:disable` directives are systematically banned unless mathematically impossible to avoid (e.g., flawed upstream library typings). Any permitted bypass MUST be immediately preceded by an inline comment explicitly justifying the architectural limitation.
- **SCAI-REQ-010 (Strict Type Safety):** The gem MUST utilize a static typing overlay (e.g., Sorbet with `# typed: strict` typing globally) to mathematically eliminate runtime type anomalies.
- **SCAI-REQ-011 (Graceful Degradation & Fail-Fast Boundaries):** The system MUST enforce fail-fast error handling at integration boundaries (e.g., encountering fatally corrupt SimpleCov telemetry raises an explicit `SCAI::PayloadError`). However, if the AST parser encounters structurally unparseable Ruby code (e.g., a dynamically generated file), it MUST gracefully degrade. Instead of crashing the entire test suite run, it MUST formally record the file as a deficit and optionally log the raw SimpleCov line coordinates for that file, explicitly denoting the parsing failure in the markdown output, before safely continuing to process the remaining valid files.

### 3.4. System Prerequisites & Dependencies
- **SCAI-REQ-015 (Ruby Version Constraint):** The gem MUST enforce a minimum Ruby version of `>= 2.6.0`. **[Refined Requirement]** Due to local environment execution constraints prohibiting the native installation of Ruby >= 3.0.0, the requirement for `prism` was archived in favor of the production-tested `whitequark/parser` gem. This ensures the environment can thoroughly execute and achieve the 100% testing mandate.
- **SCAI-REQ-016 (SimpleCov Version Constraint):** The gem MUST enforce a minimum `simplecov` dependency of `>= 0.18.0`. This is a hard structural requirement because versions older than `0.18.0` entirely lack the internal Branch Coverage telemetry required by `SCAI-REQ-005`.

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
  config.include_bypasses = true        # Default: true. Audits explicit # :nocov: ignores.
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
In strict adherence to the project's **Fail-Fast** mandate (`SCAI-REQ-011`), the formatter categorically rejects silent processing failures:
1. **Broken Code Syntax:** If the AST parser encounters structurally invalid Ruby syntax in an under-covered file, the formatter MUST immediately intercept the failure and raise an explicit `SCAI::ASTParsingError`. 
2. **Malformed Telemetry:** If the incoming SimpleCov payload is corrupted or lacks required telemetry (like branch data if using an unsupported SimpleCov version), it MUST raise an explicit `SCAI::PayloadError`.
3. **Artifact Interruption:** During a fatal crash, the Markdown artifact generation is strictly halted. The interacting AI or developer must read the terminal's `STDERR` stack trace, fix the syntax or structural failure, and re-execute the test suite before a new coverage artifact is compiled.

## 5. Example Output Reference

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
  - **Bypass Present:** Contains `# :nocov:` directive artificially ignoring coverage (Occurrence 1 of 1).

> **[WARNING] TRUNCATION NOTIFICATION:**
> The total coverage deficit report exceeded the maximum token constraint (50 kB). The report was truncated. The deficits detailed above represent the lowest-coverage (most critical) files. Please resolve these deficits to reveal the remaining uncovered files in subsequent test runs.
```

## [ARCHIVED]
The following requirements have been aggressively pruned to prevent feature bloat, respect the Single Responsibility Principle, and preserve the LLM context window.

- **[ARCHIVED] SCAI-REQ-017 (Format Flexibility):** Generating multiple structured output formats simultaneously (e.g., `JSON`, `YAML`) alongside Markdown. *Reason: Duplicates existing tools (like `simplecov-json`) and dilutes the library's fundamental goal of Markdown generation.*
- **[ARCHIVED] SCAI-REQ-018 (Test File Inference):** Inferring and rendering the expected spec file path directly in the header. *Reason: Relies on brittle, subjective heuristics that falter across diverse project architectures and test frameworks (RSpec/Minitest).*
- **[ARCHIVED] SCAI-REQ-014-b (Git Diff Prioritization):** Forcing files modified in the Git working tree to the top of the file sorting list. *Reason: Executes system calls to external version control interfaces which slows termination, creates environment coupling, and breaches the Single Responsibility Principle.*
