# SimpleCov AI Formatter

## 1. Goal & Vision

The goal of this library is to provide a custom `SimpleCov::Formatter` designed explicitly for consumption by Large Language Models (LLMs) and autonomous engineering agents. Standard coverage reporters generate massive HTML files or exhaustive JSON/console outputs detailing every line number, which overwhelms the strict token constraints of LLMs and relies on volatile reference points.

This gem will consume standard SimpleCov result sets and output a highly concise, structurally optimized **Markdown document** containing only the exact missing semantic coverage blocks, formatted to minimize token use and maximize actionable context.

## 2. Why This is the "Best" Approach for AI

Generating reports via conventional coverage tools relies heavily on line numbers (e.g., identifying deficits via transient line coordinates). This directly conflicts with secure and modern AI development standards, explicitly the **Strict Ban on Volatile Line Numbers**. Line numbers rapidly shift during code refactoring, breaking the AI's internal maps of the codebase.

This gem provides the best approach because it introduces **Semantic Resolution**:

1. **Abstract Syntax Tree (AST) Mapping:** Instead of outputting line numbers, the tool will parse the raw Ruby source files holding the missing coverage (through Prism's `parser`-compatible translation or the `parser` gem, see `SCAI-REQ-025`). It resolves the missing lines back to their stable syntactic enclosures (e.g., `MyGem::Client#connect` or `MyGem::Runner.execute`).
2. **Maximum Token Conservation:** Codebases with thousands of lines but high coverage will not bloat the prompt. Fully covered files are completely omitted from the detailed digest, and source code snippets are entirely stripped.
3. **Actionable Delta Directives:** By seeing a missing branch mapped directly to a method name, the AI can instantly search the code and write a spec targeting that exact logical boundary.

## 3. Specifications & Constraints

**Sub-Domain Identifier:** `SCAI` (SimpleCov Markdown)

Requirements revised for the 0.11.0 release carry a trailing *Revised in 0.11.0* note stating the reason for the change and the `BUGS.md` entry behind it; requirements introduced by that release state what introduced them.

### 3.1. Functional Behavior

- **SCAI-REQ-001 (Formatter Hook):** The library MUST natively integrate with SimpleCov via `SimpleCov.formatter = SimpleCov::Formatter::AIFormatter`.
- **SCAI-REQ-002 (Artifact Generation):** Upon test suite exit, the library MUST write a singular Markdown document to the location defined by `SCAI-REQ-027` (by default `ai_report.md` inside SimpleCov's coverage directory) and announce that location on standard output as defined by `SCAI-REQ-028`. If configured to do so (`output_to_console`), the formatter MUST instead safely echo the finalized digest string to `STDOUT` for immediate human readability in a terminal; the file is written in either case. If the destination cannot be written (its parent is a regular file, the disk is read-only or full, permission is denied), the formatter MUST report the path and the error on `STDERR` per `SCAI-REQ-028`, MUST still echo the digest when `output_to_console` is set, and MUST NOT raise: SimpleCov invokes formatters from its `at_exit` hook, where an exception fails an otherwise passing run. *Revised in 0.11.0: the default location now follows `SimpleCov.coverage_dir` and the write is announced (BUG-SCAI-018); an unwritable destination no longer aborts the run.*
- **SCAI-REQ-003 (Pruning Fully Covered Files):** The library MUST securely drop from the report's detailed breakdown every file at 100% on each criterion SimpleCov measured for the run — lines, branches (when branch coverage is enabled) and methods (when method coverage is measured, `SCAI-REQ-023`) — to aggressively conserve LLM token context. If the entire test suite achieves 100% coverage (i.e., there are zero deficits), the report MUST completely omit the `## Coverage Deficits` section, resulting in only the summary header (and bypasses, if any) to further reduce token usage and explicitly signify a perfect run. *Revised in 0.11.0: method coverage joined the criteria.*
- **SCAI-REQ-004 (Semantic Resolution via AST):** The library MUST parse the source of under-covered files (`SCAI-REQ-025`) to cross-reference `SimpleCov`'s exact coordinates (including line strings and column bounds) with the AST structure. Missing coverage MUST be translated by traversing up the AST to resolve the deficit into immutable semantic groupings (Module, Class, Struct/Class/Module/Data constants, Instance Method, Singleton Method, or Root Script Scope). Every resolved file MUST begin with a synthetic root node named `main` of type `Root Script Scope` spanning every line of the file (line 1 at minimum), so code outside any class or method — and bypass regions wrapping only such code — resolves to a real scope. Each deficit MUST be attributed to the innermost node spanning it; a positional `Line N` / `Lines N-M` label is permitted only when no node spans the deficit (a file that changed after coverage was recorded). The resolver MUST recognise modules and classes (including compact `class Foo::Bar` definitions), instance methods, singleton methods (`def self.x`, `def Const.x`, `def`s inside `class << self`), `class << obj` singleton classes opened on a local variable, instance variable or constant path (`obj.x`, `@ivar.x`, `Foo::Bar.x`), constants bound to `Struct.new` / `Class.new` / `Module.new` / `Data.define` blocks, and `define_method` / `define_singleton_method` blocks with a literal name; numbered-parameter and `it` blocks MUST be treated as ordinary blocks, and constant targets without a block value (`A, B = …`, `A ||= …`) MUST NOT abort resolution. A method defined at the top level MUST be named after its real owner: `Object#name` for a plain `def` (the owner SimpleCov's method coverage reports) and `main.name` for a singleton definition on the top-level object. Nodes carry line bounds only, so two definitions on one line resolve to the line's last node; a method deficit MUST be renamed after the node opening on its first line only when that node carries the method's own bare name, and MUST otherwise keep the name SimpleCov derived. *Revised in 0.11.0: the root scope replaces positional headings for top-level code (BUG-SCAI-020), value-less constant targets crashed resolution (BUG-SCAI-012), the recognised constructs are enumerated, top-level methods were named `#name` / `.name`, and a same-line neighbour could rename a method deficit.*
- **SCAI-REQ-005 (Coverage Type Segmentation):** The report MUST distinguish clearly between `Line Deficits` (unexecuted statements), `Branch Deficits` (unexecuted conditionals) and, when method coverage is measured, `Method Deficits` (methods never invoked, `SCAI-REQ-023`) to clarify the scope of the required test. *Revised in 0.11.0: method deficits added.*
- **SCAI-REQ-012 (Token Ceiling / Truncation):** To prevent prompt bloat, `max_file_size_kb` (in strict Metric units, default 50 kB) is a hard ceiling: the written file MUST never exceed it. Both the deficit section and the bypass section MUST be filled lowest-coverage file first, one semantic-node fragment at a time, and MUST stop as soon as the next fragment would no longer fit (a section heading is only written together with content). When anything was left out, the report MUST close with exactly one notice stating the limit and how many deficit files and how many bypass files were omitted or cut short; no notice is emitted when everything fits. *Revised in 0.11.0: the previous check ran only after whole deficit files had been written and did not budget the bypass section at all (BUG-SCAI-014).*
- **SCAI-REQ-013 (Directive Auditing):** The library MUST report every coverage bypass SimpleCov honoured in the run, derived from SimpleCov's own verdicts (`SourceFile#skipped_lines` and skipped branches) rather than from an independent scan of the source: `# :nocov:` pairs (including a custom `nocov_token`, an unmatched marker extending to the end of the file), inline `# simplecov:disable` comments and `# simplecov:disable line` / `# simplecov:disable branch` regions. Whatever SimpleCov did not skip — a directive inside a heredoc, or a `# simplecov:disable` on a SimpleCov release that predates it — MUST NOT be reported. A skipped region consisting solely of lines SimpleCov never counts — comments and blank lines, by SimpleCov's own line classifier — excludes nothing from any figure and MUST NOT be reported; a region holding at least one relevant line MUST be, whatever else it wraps, and skipped branches are relevant by construction. Each region MUST be attributed to the outermost semantic nodes it fully contains, or, when it sits inside a single node, to the innermost node enclosing it (the root scope at worst), listed once per node with the directive comment quoted verbatim as the reason (`# :nocov:`, `# simplecov:disable branch`, or the generic `coverage skipped by SimpleCov` when no directive can be located). This ensures that any artificial inflation of coverage metrics is fully transparent to the auditing AI. *Revised in 0.11.0: the second directive scan diverged from SimpleCov (BUG-SCAI-013); comment-only regions, including a doc comment that merely quotes a directive and which SimpleCov 1.x therefore skips, were reported as bypasses (BUG-SCAI-022).*
- **SCAI-REQ-019 (Parallel Result Merging):** Modern automated infrastructures execute tests in parallel (e.g., via `parallel_tests`), generating partial coverage sets. SimpleCov itself merges these partial result sets (per its `merge_timeout`) and invokes the formatter once with the aggregated `SimpleCov::Result`. The formatter MUST therefore process whatever `Result` it is handed transparently, without assuming a single-process run, and MUST produce the same sub-line branch snippets for a result rebuilt from `.resultset.json` (where SimpleCov stringifies branch descriptors) as for a live result, decoding the stringified descriptors with SimpleCov's own parser (`SimpleCov::SourceFile::RubyDataParser` on 1.x, the private `restore_ruby_data_structure` on 0.x) and never mutating SimpleCov's objects. *Revised in 0.11.0: column offsets were lost on the merged path (BUG-SCAI-010).*
- **SCAI-REQ-023 (Method Coverage Reporting):** On SimpleCov `>= 1.0` with `enable_coverage :method`, the header MUST carry a `**Global Method Coverage:**` line (and MUST NOT carry it when methods were not measured, keeping the header byte-identical for every other run), the `Status` and the fully-covered check (`SCAI-REQ-003`) MUST account for method coverage, and every never-invoked method MUST be listed under its node as ``**Method Deficit:** [L<start>-<end>] `Owner#name` never invoked`` (`Owner.name` for singleton methods), before the node's line and branch deficits. Method deficits MUST be derived only when the result reports method totals, so stale `methods` entries never surface on their own. *Introduced in 0.11.0 for SimpleCov 1.x.*
- **SCAI-REQ-027 (Default Report Location):** Unless `report_path` is set explicitly, the report MUST be written to `ai_report.md` inside `SimpleCov.coverage_path`, so a custom `coverage_dir` is honoured; the configuration reader MUST summarise that default as `coverage/ai_report.md`. An explicit absolute `report_path` MUST be used as-is and an explicit relative one MUST be resolved against `SimpleCov.root`, independent of the working directory at exit. *Introduced in 0.11.0 (BUG-SCAI-018).*
- **SCAI-REQ-028 (STDOUT Notice):** After writing the report the formatter MUST print `AI coverage digest written to <absolute path>` on `STDOUT`, unless `output_to_console` is set, in which case it MUST print the digest itself instead. When the report could not be written (`SCAI-REQ-002`), the notice MUST be replaced by the one-line `STDERR` message `AI coverage digest could not be written to <absolute path> (<error>)`; the digest is still printed when `output_to_console` is set. *Introduced in 0.11.0 so the artifact's location is discoverable from the test log; revised in 0.11.0 to cover an unwritable destination.*

### 3.2. Formatter Implementation & UX

- **SCAI-REQ-006 (Summary Header):** The markdown output MUST begin with a consolidated telemetry header documenting overall line percentage, branch percentage (`N/A (branch coverage not enabled)` when branch coverage was not measured), method percentage only when method coverage was measured, generation timestamp, and PASS/FAIL state, where `PASSED` requires 100% on every measured criterion. Percentages MUST be printed with one decimal, floored, so a run at 99.96% reads `99.9%` and never `100.0%` beside `FAILED`. While internal temporal logic MUST be mathematically UTC, this markdown report acts as a presentation layer and MUST dynamically convert and format the timestamp to the user's preferred local timezone. *Revised in 0.11.0: rounding could read 100.0% next to FAILED (BUG-SCAI-021); the method line was added.*
- **SCAI-REQ-007 (Context Window Preservation):** The formatter MUST NOT print surrounding code blocks or contextual snippets around the deficit. It is strictly limited to printing the exact, localized text of the isolated AST node responsible for the deficit to maximize token efficiency: a missed line quotes its stripped source line; a missed single-line branch quotes only its own arm, sliced by the byte offsets SimpleCov records for it (the `:neg` of `x.positive? ? :pos : :neg`), and a multi-line arm quotes its stripped lines joined by spaces; a missed arm that strictly contains other missed arms of the same node (the `else` arm spanning an `elsif` chain) MUST be cut to its first source line followed by `...` instead of repeating the inner arms. If a snippet exceeds `max_snippet_lines` × 80 characters (default 5 lines), the formatter MUST safely truncate it and append `...` to prevent prompt bloat. If multiple identical textual lines exist within the same semantic block, the formatter MUST disambiguate them using an occurrence index (e.g., `(Occurrence 2 of 3)`) rather than volatile line numbers. Every quoted text MUST be rendered as a code span per `SCAI-REQ-024`. *Revised in 0.11.0: the enclosing-arm rule and the code-span rule were added (BUG-SCAI-015).*
- **SCAI-REQ-014 (Deterministic Output Sorting & Token Deduplication):** To ensure output consistency and prioritize the most critical work, the detailed file reports MUST be strictly sorted. The primary sort index MUST be the **Coverage Percentage (Ascending order)** so that the worst-covered files appear sequentially at the top. The secondary tie-breaking sort MUST be the **File Path (Alphabetical order)**. Inside individual file blocks, the AST semantic nodes MUST be grouped and sorted chronologically/vertically as they naturally appear top-down within the source file (start line, then wider span first, then name, so two nodes opening on the same line always come out in the same order). To strictly enforce maximum token conservation, multiple missed lines or branches mapped to the exact same semantic node MUST be grouped under a single node heading rather than repeating the semantic boundaries; two same-named methods redefined in one file MUST remain separate groups. *Revised in 0.11.0: the tie-break within a file is now specified.*
- **SCAI-REQ-024 (Report Containment):** Every value interpolated into the report from a source file or its coverage data — snippets, node names, file paths, branch types and bypass reasons — MUST be rendered as a CommonMark code span whose backtick fence is longer than the longest backtick run inside the value (padded with spaces when the value starts or ends with a backtick), so no source text or directive comment can close the span early and inject Markdown structure into the digest; an empty value (a snippet of a file that cannot be read) MUST render as a code span holding a single space, since two bare backticks are not a code span. Snippets MUST be quoted verbatim, not rewritten. *Introduced in 0.11.0 (BUG-SCAI-015); consumers must still treat the content as untrusted, see `SECURITY.md`.*
- **SCAI-REQ-026 (Configuration Validation):** Every configuration writer MUST validate its argument at assignment time: a value of the wrong type MUST raise `TypeError` (including non-booleans passed to `output_to_console=` and `include_bypasses=`), and an out-of-range value MUST raise `ArgumentError` naming the setting — non-positive `max_file_size_kb` / `max_snippet_lines`, a `granularity` other than `:fine` / `:coarse`, a blank `report_path` or one containing a NUL byte. `SimpleCov::Formatter::AIFormatter.reset_configuration!` MUST discard the process-global configuration so the next access starts from the defaults. *Introduced in 0.11.0 (BUG-SCAI-019).*

### 3.3. Internal Gem Standards

- **SCAI-REQ-008 (Maximum Rigor Test Coverage & Anti-Coverage Paradox):** The gem's test suite MUST rigorously establish and maintain 100% deterministic line and branch coverage. However, achieving 100% execution coverage is meaningless if assertions are weak (the "Coverage Paradox"). Tests MUST NOT be tautological. The suite MUST drive the formatter through real SimpleCov objects (`SourceFile`, `Result`, and the merged `Result.from_hash` shape) built from sources written to disk, with sorbet-runtime signature checks enabled, and MUST pass on every supported SimpleCov release line; where a mock is unavoidable it MUST strictly adhere to the exact real-world interfaces and exceptions of its target (e.g., matching specific native exception classes like `Parser::SyntaxError` instead of generic `StandardError`). Furthermore, structural testing MUST employ deep, nested data fixtures rather than simple flat lists to properly validate boundary logic. Textual formatting MUST be validated using multi-line Regex matchers or whole-document equality to enforce chronological order, strictly forbidding isolated string presence assertions (like `.to include()`). The use of coverage-dodging directives (e.g., `:nocov:`) is strictly forbidden by default. They are permitted ONLY when absolute compliance is technically impossible (e.g., genuinely untestable system crashes), and any such bypass MUST be immediately preceded by a comment explicitly justifying the architectural limitation. Any randomness or time-based execution must be explicitly mocked. *Revised in 0.11.0: real SimpleCov objects replaced verifying doubles, which had hidden the merged-path regression (BUG-SCAI-010).*
- **SCAI-REQ-009 (Strict Analytical Compliance):** The gem MUST implement maximum-rigor RuboCop static analysis checks. `rubocop:disable` directives are systematically banned unless mathematically impossible to avoid (e.g., flawed upstream library typings). Any permitted bypass MUST be immediately preceded by an inline comment explicitly justifying the architectural limitation.
- **SCAI-REQ-010 (Strict Type Safety):** The gem MUST utilize a static typing overlay (Sorbet with `# typed: strict` globally, checked at `srb tc --typed strong`) to mathematically eliminate runtime type anomalies. Dependency RBIs MUST be generated by tapioca for exactly the gems `lib/` calls into and committed with the `autogenerated` sigil, with hand-written overlays only for the methods `lib/` relies on; a committed `Gemfile.lock` MUST pin the dependency set those RBIs describe. *Revised in 0.11.0: a hand-frozen hidden-definitions RBI drifted from the resolved gems (BUG-SCAI-011).*
- **SCAI-REQ-011 (Graceful Degradation):** The system MUST contain processing failures at the file level rather than aborting the test run. If the AST parser encounters structurally unparsable Ruby code (e.g., a dynamically generated file), it MUST gracefully degrade: it records the file as a deficit using the raw SimpleCov line coordinates, explicitly denoting the parsing failure in the Markdown output, before safely continuing to process the remaining valid files. Missing branch-column telemetry, unreadable or non-UTF-8 source files degrade the same way (see §4.5).
- **SCAI-REQ-020 (AST Caching & Performance):** To eliminate redundant file system I/O and overhead, the formatter MUST maintain an internal AST cache memory buffer mapping file paths to resolved syntax trees, so a file is parsed exactly once even when subjected to multiple traversals for deficit detection and bypass auditing, and MUST read a file's text exactly once, through the copy SimpleCov already loaded (`SourceFile#src`, decoded per the file's encoding comment), for snippets, occurrence indexes and bypass reasons alike. AST resolution for the bypass audit MUST only run for files SimpleCov skipped something in. *Revised in 0.11.0: sources were re-read from disk for every use (BUG-SCAI-017).*
- **SCAI-REQ-021 (Self-Documenting Mandate):** Code MUST be immediately readable by LLMs and human maintainers without relying heavily on inline comments. The code's intent MUST be derived entirely from expressive, domain-specific variable, method, and parameter naming. Generic identifiers (e.g., `result`, `group`, `f`, `n`) are strictly forbidden.
- **SCAI-REQ-022 (Zero-Bypass Formatting Strictness):** Any modifications that increase code verbosity for the sake of clarity (resulting in longer lines or larger classes) MUST be structurally accommodated. Developers MUST extract methods and reorganize logic to naturally pass all strict RuboCop limits without ever resorting to `# rubocop:disable` or inline `rescue` modifiers.
- **SCAI-REQ-029 (Quality Gates):** `bundle exec rake` MUST run every blocking gate locally — `rspec` (100% line and branch coverage), `rubocop`, `srb tc --typed strong`, `yardoc --fail-on-warning` with 100% documentation, `bundler-audit`, and `gem build --strict` followed by an install-and-require smoke test from a clean `GEM_HOME` — and CI MUST enforce those gates plus actionlint and zizmor on the workflow files, markdownlint, typos, Semgrep (`p/ruby`, `p/secrets`, `p/security-audit`, `p/github-actions`), Gitleaks over the full history, CodeQL (Ruby and workflow files), the RSpec matrix on Ruby 2.7, 3.2, 3.3, 3.4 and 4.0, and the SimpleCov compatibility matrix (0.18, 0.21, 0.22, 1.0 and 1.1 on Ruby 3.4, plus 0.18 on Ruby 2.7). Windows, JRuby, TruffleRuby, the OpenSSF Scorecard and the reek/flay/flog/debride report (`rake quality`) run non-blocking. Every GitHub Action MUST be pinned to a full commit SHA and updated by Dependabot, and a release MUST be refused unless `lib/simplecov-ai/version.rb` matches the tag and `CHANGELOG.md` has a heading for it; gem signing is opt-in via `SIMPLECOV_AI_SIGN` and a requested signature MUST be verified on the built gem. *Introduced in 0.11.0 to record the gates the release process depends on.*

### 3.4. System Prerequisites & Dependencies

- **SCAI-REQ-015 (Ruby Version Constraint):** The gem MUST enforce a minimum Ruby version of `>= 2.7.0` and is tested on MRI 2.7, 3.2, 3.3, 3.4 and 4.0 on Linux, with non-blocking runs on Windows, JRuby and TruffleRuby (neither JRuby nor TruffleRuby implements branch coverage, so only line deficits are reported there). AST parsing MUST use the backend selected per `SCAI-REQ-025`, so that every Ruby in the range is parsed with a grammar matching it. *Revised in 0.11.0: the previous text standardised on the `parser` gem alone; Prism's translation is now preferred where it exists (BUG-SCAI-016).*
- **SCAI-REQ-016 (SimpleCov Version Constraint):** The gem declares a `simplecov` dependency of `>= 0.18, < 2.0` and MUST pass its suite on every release line in that range (0.18, 0.21, 0.22, 1.0, 1.1 in CI). The `0.18` floor is API-accurate — it is the first release exposing the internal Branch Coverage telemetry required by `SCAI-REQ-005` — though the *effective installable* floor on Ruby `>= 3.0` is higher, because Bundler resolves later 0.x/1.x releases there; on Ruby 2.7 the 0.x line resolves. The `< 2.0` ceiling bounds the range across which branch enrichment has been verified. Features that only exist on SimpleCov `>= 1.0` — method coverage (`SCAI-REQ-023`) and `# simplecov:disable` directives (`SCAI-REQ-013`) — MUST be reported only where the installed SimpleCov implements them; on `< 1.0`, branch descriptors read back from `.resultset.json` are decoded by SimpleCov's `eval`-based helper (see `SECURITY.md`). *Revised in 0.11.0: the compatibility matrix and version-dependent features are stated.*
- **SCAI-REQ-025 (Parser Backend Selection):** The parsing grammar MUST be chosen once, at load time: Prism's `parser`-compatible translation with the grammar class of the running Ruby (`Prism::Translation::Parser33` … `Parser41`, the base translation class for a newer Ruby) whenever Ruby `>= 3.3`, Prism `>= 1.2` and `parser` `>= 3.3.7.2` are present; otherwise the `parser` gem's exact grammar for the running Ruby (`Parser::Ruby27` … `Parser::Ruby34`), and `parser/current` — loaded with its version-deviation warning muted — only when no exact grammar exists. The parser MUST be instantiated with all diagnostics muted so nothing is ever written to `STDERR`; syntax errors MUST still surface as `Parser::SyntaxError`; string literals whose escapes are invalid in the source encoding (`"\xf0-\xff"`) MUST be accepted as MRI accepts them; sources MUST be read as bytes and decoded per their `# encoding:` magic comment or byte-order mark. *Introduced in 0.11.0 (BUG-SCAI-016, BUG-SCAI-017).*

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

To utilize the tool, it must be explicitly required subsequent to loading SimpleCov. The developer can also optionally override internal file size constraints and custom paths if the default location (`ai_report.md` inside SimpleCov's coverage directory) does not fit their architecture.

```ruby
# spec_helper.rb or test_helper.rb
require 'simplecov'
require 'simplecov-ai'

# Optional: override default behaviors and output data.
# Every value is validated at assignment (SCAI-REQ-026): a wrong type raises TypeError,
# an out-of-range value raises ArgumentError naming the setting.
SimpleCov::Formatter::AIFormatter.configure do |config|
  # Output Targeting & File Constraints
  config.report_path = 'coverage/custom_digest.md'      # Default: ai_report.md in SimpleCov.coverage_path;
                                                        # absolute as-is, relative against SimpleCov.root
  config.max_file_size_kb = 100                         # Default: 50. Hard ceiling on the written file (kB).
  config.max_snippet_lines = 5                          # Default: 5. Snippets beyond 5 x 80 chars end in "...".
  config.output_to_console = true                       # Default: false. Prints the digest instead of the notice.

  # Structural Formats & Granularity
  config.granularity = :fine            # Default: :fine. Options: :fine (every line/branch) or :coarse (one line per node)

  # Fine-grained control over what data is stored in the digest:
  config.include_bypasses = true        # Default: true. Audits the regions SimpleCov skipped.
end

SimpleCov.start do
  enable_coverage :branch
  # SimpleCov >= 1.0 deprecates add_filter in favour of skip (same arguments):
  skip '/spec/'            # `add_filter '/spec/'` on SimpleCov < 1.0
  skip '/config/'
end

# Formatter registration: alone, or alongside other formatters.
SimpleCov.formatter = SimpleCov::Formatter::AIFormatter
# SimpleCov.formatters = [SimpleCov::Formatter::HTMLFormatter, SimpleCov::Formatter::AIFormatter]
```

`SimpleCov::Formatter::AIFormatter.reset_configuration!` discards the configuration so the next access starts from the defaults; test suites for the formatter itself use it for isolation.

### 4.3. Developer Workflow & Result Generation

The execution lifecycle remains entirely transparent from the end-user's perspective:

1. **Execution:** The developer or CI agent executes the test suite exactly as usual (e.g., `bundle exec rspec`).
2. **Collection:** `SimpleCov` tracks the executed Ruby trace points.
3. **AST Resolution:** Upon exit, the AI formatter hooks into the lifecycle, ingests the raw target coordinates, maps the deficits to their immutable AST boundaries, and prunes 100%-covered files.
4. **Persistence:** The formatter writes the digest, stopping at semantic-node granularity if `max_file_size_kb` is hit to protect token ceilings, and prints `AI coverage digest written to <path>`.

### 4.4. CI/CD & Artifact Retrieval

The formatter writes the resulting digest to a predictable path: `coverage/ai_report.md` unless `SimpleCov.coverage_dir` or `report_path` is customised, and the path is echoed on `STDOUT` at the end of the test log.

In an automated CI/CD pipeline, the engineer only needs to ensure the coverage directory is exported as an artifact. A downstream autonomous agent or LLM reviewer can simply `cat coverage/ai_report.md` directly in the pipeline to immediately review the exact unexecuted classes, methods, or logical branches, bypassing manual review of massive HTML structures and eliminating token bloat.

### 4.5. Error Handling & Failure States

In adherence to `SCAI-REQ-011`, coverage reporting is best-effort and MUST NOT abort an otherwise-passing test run. Failures are contained at the file level:

1. **Broken Code Syntax:** If the AST parser cannot process an under-covered file, that file MUST degrade gracefully to raw line numbers, annotated in the Markdown with an `AST Parsing Failed` notice (its method deficits, if any, listed the same way), while the remaining files are processed normally. A file SimpleCov skipped something in but which cannot be parsed reports no bypasses.
2. **Parser Diagnostics:** Warnings and non-fatal diagnostics from the parser MUST be dropped, never written to `STDERR`; only a genuine syntax error triggers the degradation above (`SCAI-REQ-025`).
3. **Encodings:** Sources MUST be read as bytes and decoded per their `# encoding:` magic comment or byte-order mark (a Shift_JIS file resolves); stray bytes that are invalid in the source encoding MUST NOT discard the structure of an otherwise valid file, and snippets are scrubbed so report generation never raises `Encoding::CompatibilityError`.
4. **Missing Telemetry:** If a given SimpleCov version or result shape does not provide the branch column data used for inline sub-snippets, the formatter MUST fall back to full-line snippets rather than raising.
5. **Unreadable Sources:** Files that cannot be read MUST be reported without their snippets rather than interrupting artifact generation.
6. **Misconfiguration:** Invalid configuration values fail at the assignment that supplies them (`SCAI-REQ-026`), never at exit.

## 5. Example Output Reference

Produced by a sample project on Ruby 4.0 and SimpleCov 1.1.1, trimmed by one file and one node that quotes a 300-character line:

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

With `enable_coverage :method` (SimpleCov >= 1.0) the header carries `**Global Method Coverage:** 53.3%` after the branch line and each never-invoked method precedes its node's other deficits:

```md
- `Sample::Calc#never_called`
  - **Method Deficit:** [L28-31] `Sample::Calc#never_called` never invoked
  - **Line Deficit:** [L29] `@never = 1`
  - **Line Deficit:** [L30] `@never += 1`
```

With `max_file_size_kb = 1` the same run stops after the first node of the first file in each section and closes with:

```md
> **[WARNING] TRUNCATION NOTIFICATION:**
> The report reached the maximum token constraint (1 kB) and was truncated: 3 deficit file(s) and 2 bypass file(s) omitted or cut short. Lowest-coverage files are listed first; resolve the deficits above to reveal the remaining ones in subsequent test runs.
```

## [ARCHIVED]

The following requirements have been aggressively pruned to prevent feature bloat, respect the Single Responsibility Principle, and preserve the LLM context window.

- **[ARCHIVED] SCAI-REQ-017 (Format Flexibility):** Generating multiple structured output formats simultaneously (e.g., `JSON`, `YAML`) alongside Markdown. *Reason: Duplicates existing tools (like `simplecov-json`) and dilutes the library's fundamental goal of Markdown generation.*
- **[ARCHIVED] SCAI-REQ-018 (Test File Inference):** Inferring and rendering the expected spec file path directly in the header. *Reason: Relies on brittle, subjective heuristics that falter across diverse project architectures and test frameworks (RSpec/Minitest).*
- **[ARCHIVED] SCAI-REQ-014-b (Git Diff Prioritization):** Forcing files modified in the Git working tree to the top of the file sorting list. *Reason: Executes system calls to external version control interfaces which slows termination, creates environment coupling, and breaches the Single Responsibility Principle.*
