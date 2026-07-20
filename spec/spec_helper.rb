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

require_relative '../lib/simplecov-ai'

SimpleCov::Formatter::AIFormatter.configure do |config|
  config.output_to_console = false
  config.granularity = :fine
  config.include_bypasses = true
end
SimpleCov.formatter = SimpleCov::Formatter::AIFormatter

require 'sorbet-runtime'
# The suite drives the formatter with RSpec verifying doubles (instance_double), which are not
# real instances of the classes their `sig`s require. Sorbet's runtime signature checks would
# reject those doubles, so runtime validation is turned into a no-op here. The library's value
# guards (Configuration writers, range checks) are plain Ruby and still enforced; production
# code keeps full sorbet-runtime checking.
T::Configuration.inline_type_error_handler = ->(_error, _opts) {}
T::Configuration.call_validation_error_handler = ->(_signature, _opts) {}

RSpec.configure do |config|
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end
  config.disable_monkey_patching!
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
