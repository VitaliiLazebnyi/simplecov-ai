# typed: strict
# frozen_string_literal: true

# Warnings emitted by the gem's own files fail the run (see spec/support/warnings.rb). The hook
# is installed before anything of the gem is loaded so that load-time warnings are caught too.
require_relative 'support/warnings'
GemWarnings.install! unless ENV['MUTANT']

require 'simplecov'

# The suite measures its own coverage with every criterion this Ruby and SimpleCov can provide
# and fails below 100% on each of them: lines everywhere; branches on MRI (JRuby and TruffleRuby
# implement no branch coverage); methods on SimpleCov >= 1.0, which introduced
# `enable_coverage :method`. Under mutant (MUTANT is set by .mutant.yml) the specs run once per
# mutation in forked workers, so coverage is neither measured nor enforced there; the branch
# criterion stays enabled because SimpleCov consults it while building results and the examples
# expect it on.
mri = RUBY_ENGINE == 'ruby'
branch_coverage_supported = Coverage.respond_to?(:supported?) ? Coverage.supported?(:branches) : mri
method_coverage_supported = mri && Gem::Version.new(SimpleCov::VERSION) >= Gem::Version.new('1.0')
suite_criteria = [:line]
suite_criteria << :branch if branch_coverage_supported
suite_criteria << :method if method_coverage_supported

if ENV['MUTANT']
  SimpleCov.enable_coverage(:branch) if branch_coverage_supported
else
  # Coverage tracking MUST begin before the library under test is required, otherwise the gem's
  # own lines are never instrumented and the 100% mandate below is vacuously satisfied.
  SimpleCov.start do
    suite_criteria.each { |criterion| enable_coverage(criterion) }
    add_filter '/spec/'
    minimum_coverage(suite_criteria.to_h { |criterion| [criterion, 100] })
  end
end

require 'simplecov-ai'

unless ENV['MUTANT']
  SimpleCov::Formatter::AIFormatter.configure do |config|
    config.output_to_console = false
    config.granularity = :fine
    config.include_bypasses = true
  end
  SimpleCov.formatter = SimpleCov::Formatter::AIFormatter
end

# The suite drives the formatter with real SimpleCov objects (see spec/support), so
# sorbet-runtime's signature checks stay fully enabled: every `sig` in lib/ is enforced while
# the examples run, exactly as it is for users.
Dir[File.join(__dir__, 'support', '**', '*.rb')].sort.each { |support_file| require support_file }

RSpec.configure do |config|
  config.include SimpleCovFixtures
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end
  config.disable_monkey_patching!
  config.expect_with :rspec do |expectations|
    expectations.syntax = :expect
  end

  # SimpleCov reports aggregate method figures for any Result while the method criterion is
  # enabled (its FileList filters statistics by the global criteria), which would put a method
  # line into every report the examples build. Each example therefore runs with the suite's
  # method criterion switched off and opts in through `measuring_methods`; the criterion is
  # restored afterwards so the suite's own result at exit still carries it.
  config.around do |example|
    criteria_before_example = SimpleCov.coverage_criteria.dup
    SimpleCov.coverage_criteria.delete(:method)
    example.run
  ensure
    SimpleCov.coverage_criteria.replace(criteria_before_example)
  end

  config.after(:suite) { GemWarnings.verify! unless ENV['MUTANT'] }
end
