# typed: false
# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

# Measures the fixture's real coverage through the suite's own Coverage session and formats it.
# Under mutant no coverage session runs (see spec_helper.rb), so these examples are excluded
# there (`mutant: false`); the formatter's subjects are covered by the exact-report specs. On an
# engine that records no branch coverage the example is skipped after the report is produced.
RSpec.describe SimpleCov::Formatter::AIFormatter, mutant: false do
  let(:fixture_path) { File.expand_path('../../fixtures/metaprogramming_constructs.rb', __dir__) }
  let(:report_path) { 'coverage/metaprogramming_test_ai_report.md' }
  # Each construct as its own node followed by its missed arm, in source order.
  let(:expected_lines) do
    deficit = '^  - \\*\\*Branch Deficit:\\*\\* \\[L\\d+\\] Missing coverage for `%s` branch: `%s`$'
    ['^- `MetaprogrammingConstructs#dynamic_instance_method`$', format(deficit, 'else', ':dynamic_false'),
     '^- `MetaprogrammingConstructs\\.dynamic_class_method`$', format(deficit, 'else', ':singleton_case_else'),
     '^- `MetaprogrammingConstructs#evaled_method`$', format(deficit, 'else', ':evaled_false'),
     '^- `MetaprogrammingConstructs#method_missing`$', format(deficit, 'else', 'super'),
     '^- `MetaprogrammingConstructs\\.eigen_method`$', format(deficit, 'then', ':eigen_false')]
  end

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

    described_class.configure do |config|
      config.report_path = report_path
      config.output_to_console = false
    end
    capture_stdout { described_class.new.format(session_result(fixture_path)) }
    # Formatting proves that what this engine's Coverage recorded builds a Result and renders; the
    # example asserts branch deficits, which only an engine recording branches can produce.
    skip 'this engine records no branch coverage' unless branch_coverage_measurable?
  end

  after do
    described_class.reset_configuration!
    FileUtils.rm_f(report_path)
  end

  it 'lists each construct as its own node with the missed arm, in source order' do
    expect(File.read(report_path)).to match(Regexp.new(expected_lines.join('.*'), Regexp::MULTILINE))
  end
end
