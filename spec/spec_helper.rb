# typed: strict
# frozen_string_literal: true

require 'simplecov'
require_relative '../lib/simplecov-ai'

SimpleCov::Formatter::AIFormatter.configure do |config|
  config.output_to_console = true
  config.granularity = :fine
  config.include_bypasses = true
end

# Coverage mandates (SimpleCov)
SimpleCov.start do
  enable_coverage :branch
  add_filter '/spec/'
  add_filter '/config/'
  formatter SimpleCov::Formatter::AIFormatter
end

require 'sorbet-runtime'
# Disable runtime type errors for RSpec testing of failure paths
T::Configuration.inline_type_error_handler = ->(_, _) {}
T::Configuration.call_validation_error_handler = ->(_, _) {}

RSpec.configure do |config|
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end
  config.disable_monkey_patching!
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
