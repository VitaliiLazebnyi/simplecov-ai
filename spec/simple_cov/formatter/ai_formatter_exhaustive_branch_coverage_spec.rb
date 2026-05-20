# typed: false
# frozen_string_literal: true

require 'spec_helper'
require 'coverage'
require 'tmpdir'
require 'fileutils'

# Integration tests require specific setup and multi-step assertions
# that naturally violate some RSpec style guidelines.
# Justification: Integration tests setup
RSpec.describe SimpleCov::Formatter::AIFormatter do
  let(:fixture_path) { File.expand_path('../../fixtures/exhaustive_branching.rb', __dir__) }
  let(:report_path) { 'coverage/exhaustive_test_ai_report.md' }

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
    rescue NoMatchingPatternError => e
      e.class # Intentionally swallowed to execute specific path
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
    formatter.format(result)
  end

  after do
    FileUtils.rm_f(report_path)
  end

  # Justification: Integration tests require multi-step assertions on a single generated report.
  it 'generates a report with standard control flow deficit snippets' do
    report_content = File.read(report_path)

    expect(report_content).to include(
      'Missing coverage for `else` branch: `:if_false`',
      'Missing coverage for `then` branch: `:unless_true`',
      'Missing coverage for `else` branch: `:ternary_false`',
      'Missing coverage for `when` branch: `:case_two`',
      'Missing coverage for `else` branch: `:case_else`',
      'Missing coverage for `then` branch: `obj&.name`'
    )
  end

  it 'generates a report with loop and pattern matching deficit snippets' do
    report_content = File.read(report_path)

    expect(report_content).to include(
      'Missing coverage for `body` branch: `break :while_break`',
      'Missing coverage for `body` branch: `break :until_break`',
      'Missing coverage for `in` branch: `:pattern_two`',
      'Missing coverage for `else` branch: `:pattern_else`'
    )
  end

  it 'generates a report with edge case deficit snippets' do
    report_content = File.read(report_path)

    expect(report_content).to include(
      'Missing coverage for `else` branch: `:inline_yes if cond`',
      'Missing coverage for `else` branch: `:multiple_when_else`',
      'Missing coverage for `then` branch: `obj&.a`',
      'Missing coverage for `then` branch: `obj&.a&.b`'
    )
  end
end
