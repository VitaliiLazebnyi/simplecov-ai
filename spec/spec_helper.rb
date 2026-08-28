# typed: strict
# frozen_string_literal: true

# Warnings emitted by the gem's own files fail the run (see spec/support/warnings.rb). The hook
# is installed before anything of the gem is loaded so that load-time warnings are caught too.
require_relative 'support/warnings'
gem_warnings = GemWarnings.new
gem_warnings.install! unless ENV['MUTANT']

require 'coverage'
require 'simplecov'
# Loaded ahead of the other support files: it answers what this Ruby's Coverage can record.
require_relative 'support/simplecov_fixtures'

# The suite measures its own coverage with every criterion this Ruby and SimpleCov can provide:
# lines everywhere; branches where the engine records them (MRI; JRuby and TruffleRuby implement
# no branch coverage); methods on SimpleCov >= 1.0, which introduced `enable_coverage :method`,
# again where the engine records them. On MRI it fails below 100% on each of them. That mandate
# is MRI's gate alone: JRuby 9.4 reports the lines of a multi-line `sig do … end` block as
# unexecuted, and TruffleRuby 25 never counts a `case` line or an index assignment inside an `if`
# within a block — lines MRI records as executed — so 100% is unreachable there and the engine
# runs only report what they measured (the digest at coverage/ai_report.md lists it). Under
# mutant (MUTANT is set by .mutant.yml) the specs run once per mutation in forked workers, so
# coverage is neither measured nor enforced there; the branch criterion stays enabled because
# SimpleCov consults it while building results and the examples expect it on.
mri = RUBY_ENGINE == 'ruby'
branch_coverage_supported = SimpleCovFixtures::Engine.measures?(:branches)
method_coverage_supported = SimpleCovFixtures::Engine.measures?(:methods) &&
                            Gem::Version.new(SimpleCov::VERSION) >= Gem::Version.new('1.0')
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
    # SimpleCov >= 1.1 renamed add_filter to skip and deprecates the old name.
    respond_to?(:skip) ? skip('/spec/') : add_filter('/spec/')
    minimum_coverage(suite_criteria.to_h { |criterion| [criterion, 100] }) if mri
  end
end

# On an engine that records no branches the branch criterion is switched on all the same — after
# `SimpleCov.start`, so `Coverage.start` is never asked for data the engine cannot produce — for
# the examples' sake: see the engine gate lifted in the RSpec configuration below.
SimpleCov.coverage_criteria << :branch unless branch_coverage_supported

require 'simplecov-ai'

# The suite's own digest is written with the default configuration; every example leaves the
# process-global configuration at its defaults as well (see the `after` hook below).
SimpleCov.formatter = SimpleCov::Formatter::AIFormatter unless ENV['MUTANT']

# The suite drives the formatter with real SimpleCov objects (see spec/support), so
# sorbet-runtime's signature checks stay fully enabled: every `sig` in lib/ is enforced while
# the examples run, exactly as it is for users.
Dir[File.join(__dir__, 'support', '**', '*.rb')].sort.each { |support_file| require support_file }

RSpec.configure do |config|
  config.include SimpleCovFixtures
  config.include ReportExpectations
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

  # JRuby and TruffleRuby record no branch or method coverage, and SimpleCov reports the branch
  # and method statistics of a result only where the engine could have produced them:
  # `SimpleCov.branch_coverage?` is hard-wired false on JRuby in 0.18–0.22 and asks
  # `Coverage.supported?` from 1.0 on, as does `method_coverage?`, and FileList#coverage_statistics
  # (hence Result#total_branches and #total_methods) is gated on them. The branch and method data
  # the examples build by hand (spec/support/simplecov_fixtures.rb) would therefore vanish from
  # every report on those engines. For the examples the engine gate is lifted and the predicates
  # answer from the criteria alone (`:branch` is switched on above, `:method` per example through
  # `measuring_methods`), so the formatter's branch and method rendering is exercised with
  # hand-built data on every engine; spec/integration/end_to_end_spec.rb proves what a real run
  # on such an engine produces (an N/A branch line and line deficits only). An example that stubs
  # a predicate itself (ai_formatter_spec.rb) still wins, as its `allow` comes later.
  config.before do
    unless branch_coverage_supported
      allow(SimpleCov).to receive(:branch_coverage?) { SimpleCov.coverage_criterion_enabled?(:branch) }
    end
    if SimpleCov.respond_to?(:method_coverage?) && !method_coverage_supported
      allow(SimpleCov).to receive(:method_coverage?) { SimpleCov.coverage_criterion_enabled?(:method) }
    end
  end

  # The formatter's configuration is process-global: what an example configures (a report path,
  # say) must reach neither the next example nor the suite's own digest at exit.
  config.after { SimpleCov::Formatter::AIFormatter.reset_configuration! }

  config.after(:suite) { gem_warnings.verify! unless ENV['MUTANT'] }
end
