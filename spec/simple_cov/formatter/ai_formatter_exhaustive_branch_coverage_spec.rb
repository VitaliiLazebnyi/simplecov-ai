# typed: false
# frozen_string_literal: true

require 'spec_helper'
require 'coverage'
require 'tmpdir'
require 'fileutils'

# Measures the fixture's real coverage through the suite's own Coverage session and formats it.
# Under mutant no coverage session runs (see spec_helper.rb), so these examples are excluded
# there (`mutant: false`); the formatter's subjects are covered by the exact-report specs.
RSpec.describe SimpleCov::Formatter::AIFormatter, mutant: false do
  let(:fixture_path) { File.expand_path('../../fixtures/exhaustive_branching.rb', __dir__) }
  let(:report_path) { 'coverage/exhaustive_test_ai_report.md' }
  # Every method with a missed arm or line, in source order. `&&`, `||` and their assignment
  # forms produce no branch data in Ruby's coverage, and neither does the one-line `in` pattern
  # since Ruby 3.4 compiles with Prism, so those methods have no deficit.
  let(:expected_headings) do
    headings = %w[
      ExhaustiveBranching.test_if_else ExhaustiveBranching.test_unless_else ExhaustiveBranching.test_ternary
      ExhaustiveBranching.test_case_when ExhaustiveBranching.test_safe_nav ExhaustiveBranching.test_while_loop
      ExhaustiveBranching.test_until_loop ExhaustiveBranching.test_pattern_matching
      ExhaustiveBranching.test_inline_if ExhaustiveBranching.test_multiple_when
      ExhaustiveBranching.test_chained_safe_nav ExhaustiveBranching.test_inline_rescue
      ExhaustiveBranching.test_begin_rescue
    ]
    next headings if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('3.4')

    one_line_pattern = 'ExhaustiveBranching.test_one_line_pattern'
    headings.insert(headings.index('ExhaustiveBranching.test_chained_safe_nav'), one_line_pattern)
  end

  before do
    require_relative '../../fixtures/exhaustive_branching'

    # Execute specific paths to ensure at least one missed branch per construct
    ExhaustiveBranching.test_if_else(true)
    ExhaustiveBranching.test_unless_else(true)
    ExhaustiveBranching.test_ternary(true)
    ExhaustiveBranching.test_case_when(1)
    ExhaustiveBranching.test_safe_nav(nil)
    ExhaustiveBranching.test_logical_and(true, true)
    ExhaustiveBranching.test_logical_or(true, true)
    ExhaustiveBranching.test_logical_or_assign(nil, true)
    ExhaustiveBranching.test_logical_and_assign(true, true)
    ExhaustiveBranching.test_while_loop(false)
    ExhaustiveBranching.test_until_loop(true)
    ExhaustiveBranching.test_pattern_matching(1)
    ExhaustiveBranching.test_begin_rescue(false)

    # New edge cases
    ExhaustiveBranching.test_inline_if(true)
    ExhaustiveBranching.test_multiple_when(1)

    # Justification: Deliberately swallowing exception to execute specific path.
    begin
      ExhaustiveBranching.test_one_line_pattern({ a: 1 })
    rescue NoMatchingPatternError => error
      error.class # Intentionally swallowed to execute specific path
    end
    ExhaustiveBranching.test_chained_safe_nav(nil)

    described_class.configure do |c|
      c.report_path = report_path
      c.output_to_console = false
    end

    coverage_result = Coverage.peek_result
    fixture_cov = coverage_result.select { |k, _v| k == fixture_path }
    original_filters = SimpleCov.filters.dup
    SimpleCov.filters.clear
    result = SimpleCov::Result.new(fixture_cov)
    SimpleCov.filters.replace(original_filters)

    formatter = described_class.new
    capture_stdout { formatter.format(result) }
  end

  after do
    FileUtils.rm_f(report_path)
  end

  # The deficit lines the report must contain, in the order the fixture defines the constructs
  # (nodes are listed in source order, so the report must list these lines in this order too).
  def ordered_deficit_lines(*snippets)
    lines = snippets.map do |snippet|
      "^  - \\*\\*Branch Deficit:\\*\\* \\[L\\d+(?:-\\d+)?\\] #{Regexp.escape(snippet)}$"
    end
    Regexp.new(lines.join('.*'), Regexp::MULTILINE)
  end

  it 'lists the standard control-flow deficits in source order under their methods' do
    pattern = ordered_deficit_lines(
      'Missing coverage for `else` branch: `:if_false`',
      'Missing coverage for `then` branch: `:unless_true`',
      'Missing coverage for `else` branch: `:ternary_false`',
      'Missing coverage for `when` branch: `:case_two`',
      'Missing coverage for `else` branch: `:case_else`',
      'Missing coverage for `then` branch: `obj&.name`'
    )
    expect(File.read(report_path)).to match(pattern)
  end

  it 'lists the loop and pattern-matching deficits in source order' do
    pattern = ordered_deficit_lines(
      'Missing coverage for `body` branch: `break :while_break`',
      'Missing coverage for `body` branch: `break :until_break`',
      'Missing coverage for `in` branch: `:pattern_two`',
      'Missing coverage for `else` branch: `:pattern_else`'
    )
    expect(File.read(report_path)).to match(pattern)
  end

  it 'lists the edge-case deficits in source order' do
    pattern = ordered_deficit_lines(
      'Missing coverage for `else` branch: `:inline_yes if cond`',
      'Missing coverage for `else` branch: `:multiple_when_else`',
      'Missing coverage for `then` branch: `obj&.a`',
      'Missing coverage for `then` branch: `obj&.a&.b`'
    )
    expect(File.read(report_path)).to match(pattern)
  end

  it 'attributes every deficit to a method of the fixture module, in source order' do
    expect(File.read(report_path).scan(/^- `(ExhaustiveBranching\.\w+)`$/).flatten).to eq(expected_headings)
  end
end
