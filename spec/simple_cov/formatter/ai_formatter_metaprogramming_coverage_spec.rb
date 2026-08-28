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
  let(:fixture_path) { File.expand_path('../../fixtures/metaprogramming_constructs.rb', __dir__) }
  let(:report_path) { 'coverage/metaprogramming_test_ai_report.md' }

  # We use a class variable or standard local variable within a shared context to avoid before(:all)
  # But since this is a coverage test, we just run it in a single before block.
  before do
    require_relative '../../fixtures/metaprogramming_constructs'

    target = MetaTarget.new

    # 1. define_method
    target.dynamic_instance_method(true)

    # 2. define_singleton_method
    MetaprogrammingConstructs.dynamic_class_method(1)

    # 3. class_eval
    target.evaled_method(true)

    # 4. method_missing
    target.magic_test
    target.respond_to?(:magic_test)

    # 5. Singleton class / Eigenclass
    MetaprogrammingConstructs.eigen_method(true)

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

  # Justification: Integration tests require multi-step assertions on a single generated report.
  it 'generates a report with expected branch deficit snippets for metaprogramming constructs' do
    report_content = File.read(report_path)

    expect(report_content).to include(
      'Missing coverage for `else` branch: `:dynamic_false`',
      'Missing coverage for `else` branch: `:singleton_case_else`',
      'Missing coverage for `else` branch: `:evaled_false`',
      'Missing coverage for `else` branch: `super`',
      'Missing coverage for `then` branch: `:eigen_false`'
    )
  end
end
