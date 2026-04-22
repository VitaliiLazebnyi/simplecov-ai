# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'

module SimpleCov
  module Formatter
    class AIFormatter
      # The semantic version identifier for the gem, used for dependency resolution
      # and enforcing compatibility across upgrades.
      VERSION = T.let('0.1.0', String)
    end
  end
end
