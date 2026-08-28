# typed: strict
# frozen_string_literal: true

require 'simplecov'

# Coverage tracking MUST begin before the library under test is required, otherwise the gem's
# own lines are never instrumented and the 100% mandate below is vacuously satisfied.
SimpleCov.start do
  enable_coverage :branch
  add_filter '/spec/'
  minimum_coverage line: 100, branch: 100
end

require 'simplecov-ai'

SimpleCov::Formatter::AIFormatter.configure do |config|
  config.output_to_console = false
  config.granularity = :fine
  config.include_bypasses = true
end
SimpleCov.formatter = SimpleCov::Formatter::AIFormatter

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
end
