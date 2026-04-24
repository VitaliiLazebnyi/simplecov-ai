# Active Defects & Anomalous Behaviors

This document tracks active bugs and behavioral deltas in the `simplecov-ai` project. All entries must include a unique identifier, link to a specific `SCAI-REQ`, and detail the root cause alongside the expected behavioral delta.

## BUG-SCAI-001: Global Branch Coverage Always Reports 0.0%

**Violated Requirement:** [SCAI-REQ-006] Summary Header (Branch Percentage)
**Status:** Remediated in v0.10.x
**Date Logged:** 2026-04-24

### 1. Architectural Description of the Defect

When the `simplecov-ai` formatter evaluates branch coverage statistics—even in projects demonstrating positive, mathematically proven branch coverage (e.g., `50%` coverage confirmed via `simplecov-html`)—the generated markdown artifact (`coverage/ai_report.md`) erroneously reports:

```markdown
**Global Branch Coverage:** 0.0%
```

This represents a critical anomaly that violates **SCAI-REQ-006**, which dictates that the summary header must accurately document the overall branch percentage, thereby providing an incorrect, zero-state telemetry indicator to the consuming autonomous agent.

### 2. Deep Dive: Root Cause Analysis

The defect resides in the `calculate_branch_pct` method within `lib/simplecov-ai/markdown_builder.rb`.

#### The Flawed Implementation
```ruby
sig { returns(Float) }
def calculate_branch_pct
  return 0.0 unless @result.respond_to?(:covered_branches) && @result.respond_to?(:total_branches)

  T.cast(@result.covered_branches, Float) / @result.total_branches * 100
rescue StandardError
  0.0
end
```

#### The Type Coercion Fallacy
The bug is caused by a fundamental misunderstanding of Sorbet's `T.cast` interface versus native Ruby object coercion mechanisms. 

When the `simplecov` coverage suite executes, `@result.covered_branches` and `@result.total_branches` return primitive `Integer` instances (e.g., `3` covered branches out of `6` total). The original author attempted to force floating-point division by casting the numerator to a `Float`:

```ruby
T.cast(@result.covered_branches, Float) # e.g., T.cast(3, Float)
```

However, Sorbet's `T.cast` is strictly a **Type Assertion** boundary used for narrowing or overruling the static analyzer; it is **NOT** a data mutator or a type coercer. It asserts to the runtime that the evaluated object *is already* of the target class. 

#### The Execution Trace (Silent Failure)
When the Ruby runtime executes `T.cast(3, Float)`, the `sorbet-runtime` interceptor fires and performs a strict identity check (`3.is_a?(Float)`). Because `3` is an `Integer`, the assertion fails violently and immediately raises a fatal `TypeError`.

**Example Sorbet Stack Trace (Reproduced Behavior):**
```text
TypeError: T.cast: Expected type Float, got type Integer with value 3
  from sorbet-runtime/lib/types/private/casts.rb:42:in `cast'
  from lib/simplecov-ai/markdown_builder.rb:90:in `calculate_branch_pct'
  from lib/simplecov-ai/markdown_builder.rb:81:in `write_header'
  from lib/simplecov-ai/markdown_builder.rb:50:in `build'
```

#### The "Rescue" Mask
This fatal `TypeError` crashes the `calculate_branch_pct` method. Unfortunately, the method was wrapped in a highly permissive `rescue StandardError` block (intended originally to protect against dividing by zero or corrupted `SimpleCov::Result` payloads). The rescue block catches the `TypeError`, swallows the stack trace silently, and returns the hardcoded fallback value `0.0`. 

The system incorrectly assumes that a missing `total_branches` value occurred, when in reality, the system intentionally crashed itself due to improper Sorbet utilization.

### 3. Expected Behavioral Delta & Remediation Strategy

To remediate this, the formatter must rely on native Ruby numeric coercion (`to_f`) for mathematics, while satisfying the `typed: strict` static analyzer checks.

#### Remediation Protocol
1. **Remove `T.cast`**: The static analyzer knows that `total_branches` and `covered_branches` yield `Integer` values natively (as defined in the `simplecov` RBI interfaces).
2. **Handle Zero Division Safely**: Instead of blindly rescuing `StandardError` to catch `ZeroDivisionError`, we proactively guard against a `0` denominator.
3. **Execute Ruby Coercion**: We use `#to_f` on the integer to trigger floating point division.

#### The Corrected Implementation (Target State)
```ruby
sig { returns(Float) }
def calculate_branch_pct
  return 0.0 unless @result.respond_to?(:covered_branches) && @result.respond_to?(:total_branches)

  total = @result.total_branches
  return 0.0 if total.zero? # Mathematical safeguard preventing ZeroDivisionError

  covered = @result.covered_branches
  covered.to_f / total * 100.0 # Native float coercion (e.g., 3.0 / 6 * 100.0)
rescue StandardError
  0.0 # Reserved exclusively for catastrophically malformed payloads
end
```

### 4. Verification & Testing

The remediation MUST be preceded by a failing `RSpec` test confirming the `0.0%` regression. 

**Example Test Codification (`spec/simple_cov/formatter/ai_formatter_spec.rb`):**
```ruby
context 'when writing a basic digest' do
  let(:mock_result) do
    instance_double(
      SimpleCov::Result,
      covered_percent: 90.0,
      covered_branches: 10,  # Integer
      total_branches: 20,    # Integer
      files: [mock_file]
    )
  end

  it('includes the correct branch coverage') do
    formatter.format(mock_result)
    # Expected: 10.to_f / 20 * 100.0 = 50.0
    expect(File.read(config.report_path)).to include('**Global Branch Coverage:** 50.0%') 
  end
end
```
Executing this test suite against the remediated target code yields a 100% Pass rate, closing the defect while maintaining strict Sorbet validation without the use of `T.unsafe`.

## BUG-SCAI-002: Innermost Semantic Mapping Failure (SCAI-REQ-004)

**Violated Requirement:** [SCAI-REQ-004] Semantic Resolution via AST
**Status:** Remediated in v0.10.x
**Date Remediated:** 2026-04-25


### Description
The `DeficitGrouper` fails to map a line or branch deficit to its most precise, innermost semantic boundary (e.g., an Instance Method). Instead, it erroneously attributes the deficit to the outermost enclosure (e.g., the parent `Module` or `Class`).

### Root Cause Analysis
In `lib/simplecov-ai/markdown_builder/deficit_grouper.rb`, the `group_missed_lines` and `group_missed_branches` methods use `.find` to locate the matching node:
```ruby
node = @nodes.find { |n| line_num.between?(n.start_line, n.end_line) }
```
Because the `ASTResolver#traverse` algorithm uses a pre-order traversal (parent nodes are appended to the array *before* their children), the outermost `Module` or `Class` will always be the *first* node found that encases the target line number. The traversal stops immediately, ignoring the deeper, more accurate `Method` node.

### Expected Behavioral Delta
The grouper must traverse the nodes in reverse order (or select the node with the narrowest line delta) to ensure the innermost semantic node is selected.
```ruby
node = @nodes.reverse.find { |n| line_num.between?(n.start_line, n.end_line) }
```

## BUG-SCAI-003: Silent AST Parsing Degradation (SCAI-REQ-011)

**Violated Requirement:** [SCAI-REQ-011] Graceful Degradation & Fail-Fast Boundaries
**Status:** Remediated in v0.10.x
**Date Remediated:** 2026-04-25


### Description
When the `parser` gem encounters structurally invalid Ruby code, the system degrades silently, failing to output the mandated `**ERROR:** AST Parsing Failed` warning.

### Root Cause Analysis
In `lib/simplecov-ai/ast_resolver.rb`, a `Parser::SyntaxError` is rescued and returns an empty array `[]`. 
In `lib/simplecov-ai/markdown_builder/deficit_compiler.rb`:
```ruby
nodes = @builder.try_resolve_ast(file.filename)
nodes ? process_deficits(buffer, file, nodes) : format_raw_deficits(buffer, file)
```
In Ruby, an empty array `[]` evaluates to `true` (truthy). Therefore, the ternary operator evaluates to `process_deficits` with zero nodes instead of calling `format_raw_deficits`, completely bypassing the error warning logic.

### Expected Behavioral Delta
`try_resolve_ast` should return `nil` upon syntax error, OR `deficit_compiler.rb` must explicitly check `nodes.nil?` instead of relying on implicit truthiness.

## BUG-SCAI-004: Duplicated Bypass Reporting / Token Bloat

**Violated Requirement:** [SCAI-REQ-014] Deterministic Output Sorting & Token Deduplication
**Status:** Remediated in v0.10.x
**Date Remediated:** 2026-04-25


### Description
A single `:nocov:` directive is reported multiple times in the `Ignored Coverage Bypasses` section for the same file, severely violating the token conservation mandate.

### Root Cause Analysis
`ASTResolver#extract_bypasses` evaluates whether a `:nocov:` comment falls within `start_line` and `end_line` for *every* node. If a `:nocov:` is inside a method, it technically falls within the method's bounds, the class's bounds, and the module's bounds. 
`BypassCompiler#fetch_bypassed_nodes` collects *all* nodes with bypasses, meaning the single `:nocov:` comment causes the `Module`, `Class`, and `Method` to all be independently reported as containing a bypass.

### Expected Behavioral Delta
Bypasses must be attributed exclusively to their most specific, innermost semantic node (similar to BUG-SCAI-002) and deduplicated before compiling the markdown output.

## BUG-SCAI-005: Chronological Sorting Violation (SCAI-REQ-014)

**Violated Requirement:** [SCAI-REQ-014] Deterministic Output Sorting & Token Deduplication
**Status:** Remediated in v0.10.x
**Date Remediated:** 2026-04-25


### Description
Inside individual file blocks, semantic nodes are not consistently sorted chronologically top-down if a file contains both line and branch deficits.

### Root Cause Analysis
In `DeficitGrouper.build`, `group_missed_lines` is executed first, followed entirely by `group_missed_branches`. The results are appended into a standard Ruby Hash (`@node_deficits`). If a branch deficit occurs on Line 5, and a line deficit occurs on Line 20, the Node at Line 20 is inserted into the Hash first. The Node at Line 5 is inserted second. When the Hash is iterated, Line 20 will render *before* Line 5, violating chronological sorting.

### Expected Behavioral Delta
After grouping, the `@node_deficits` structure must be explicitly sorted by the `semantic_node.start_line` before yielding to the markdown compiler.

## BUG-SCAI-006: Timezone Formatting Deviation (SCAI-REQ-006)

**Violated Requirement:** [SCAI-REQ-006] Summary Header
**Status:** Remediated in v0.10.x
**Date Remediated:** 2026-04-25


### Description
The markdown artifact timestamp diverges from the required example format. It outputs `2026-04-25 00:39:38 +0900` instead of `2026-04-21T23:40:44+09:00 (Local Timezone)`.

### Root Cause Analysis
`MarkdownBuilder#write_header` injects `Time.now` directly into the string buffer:
```ruby
@buffer.puts "**Generated At:** #{Time.now}"
```
This triggers Ruby's default `#to_s` for `Time`, rather than an ISO8601 string concatenated with the explicit "(Local Timezone)" indicator specified in the architectural requirements.

### Expected Behavioral Delta
The system should explicitly format the time via `Time.now.iso8601` (requiring `require 'time'`) and append ` (Local Timezone)`.

## BUG-SCAI-007: Presentation & Formatting Misalignments

**Violated Requirement:** [SCAI-REQ-006 & SCAI-REQ-007] Reporting Fidelity
**Status:** Remediated in v0.10.x
**Date Remediated:** 2026-04-25

### Description
There are a few minor, but noticeable, textual deviations in the generated markdown output when compared to the strict examples provided in `REQUIREMENTS.md`. While the core functionality is intact, the presentation layer lacks requested fidelity.

### Root Cause Analysis
1. **Truncation Warning Clause:** The `write_truncation_warning` method omits specific phrases like `(most critical)` and `in subsequent test runs.` from the alert block.
2. **Bypass Deduplication Suffix:** `write_file_bypasses` hardcodes the text `- **Bypass Present:** Contains :nocov: directive.`. It fails to calculate and append the required occurrence index (e.g., `(Occurrence 1 of X)`).
3. **Occurrence Tag Spacing:** The `calculate_occurrence` helper appends a trailing space instead of a trailing period `(Occurrence X of Y) `, leading to formatting inconsistencies when injected into the Line Deficit vs. Branch Deficit strings.

### Risk
Low severity, but it violates the strict UI/UX presentation specifications and could confuse automated parsing tools expecting the exact string template.

### Expected Behavioral Delta
Align all string concatenations perfectly with the requested templates in `REQUIREMENTS.md`.

## BUG-SCAI-008: `NoMethodError` Vulnerability in Metric Calculations

**Violated Requirement:** [SCAI-REQ-002] Fail-Fast Error Handling & Type Safety
**Status:** Remediated in v0.10.x
**Date Remediated:** 2026-04-25

### Description
The `calculate_branch_pct` logic is vulnerable to a `NoMethodError` if `SimpleCov` returns `nil` for branch statistics (which can occur in legacy environments or specific missing configs). 

### Root Cause Analysis
In `lib/simplecov-ai/markdown_builder.rb`:
```ruby
total = @result.total_branches
return 0.0 if total.zero?
```
If `total` is `nil`, `.zero?` will trigger a fatal `NoMethodError: undefined method 'zero?' for nil:NilClass`. This crash is currently only being caught because the entire method is wrapped in a `rescue StandardError`, swallowing the error and defaulting to `0.0`. 

### Risk
High risk of obfuscating true systemic failures. Relying on a broad `rescue StandardError` to handle predictable `nil` evaluations violates the "Fail-Fast" and explicit typing mandates.

### Expected Behavioral Delta
Implement explicit `nil` handling logic:
```ruby
return 0.0 if total.nil? || total.zero?
```

## BUG-SCAI-009: RuboCop Static Analysis Regressions

**Violated Requirement:** [SCAI-REQ-001] 100% Zero-Tolerance for Warnings
**Status:** Remediated in v0.10.x
**Date Remediated:** 2026-04-25

### Description
The recent structural fixes applied to `ASTResolver` and `DeficitGrouper` to resolve chronological sorting and bypass logic have inadvertently introduced severe RuboCop static analysis violations, breaking the CI pipeline's strict zero-warning mandate.

### Root Cause Analysis
Running `bundle exec rubocop` yields the following offenses:
1. `lib/simplecov-ai/ast_resolver.rb:97:9` - `Metrics/AbcSize` is too high (21.91/17) for `assign_bypasses`.
2. `lib/simplecov-ai/ast_resolver.rb:115:41` - `Lint/UnusedMethodArgument` for `comments` in `extract_node_metadata`.
3. `lib/simplecov-ai/markdown_builder/deficit_grouper.rb:25:11` - `Metrics/MethodLength` is too long (13/10) for `self.build`.
4. `lib/simplecov-ai/markdown_builder/deficit_grouper.rb:43:11` - `Metrics/AbcSize` is too high (17.03/17) for `group_missed_lines`.

### Risk
Immediate CI/CD pipeline failure. Code cannot be merged until it satisfies the configured static analysis threshold.

### Expected Behavioral Delta
Refactor `self.build`, `group_missed_lines`, and `assign_bypasses` into smaller, highly-cohesive private helper methods to reduce branch complexity. Remove the unused `comments` parameter from `extract_node_metadata` and its downstream caller chain.
