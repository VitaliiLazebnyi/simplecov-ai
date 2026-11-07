# Copyright (c) 2026 Vitalii Lazebnyi
# typed: strong
# frozen_string_literal: true

require 'sorbet-runtime'

module SimpleCov
  module Formatter
    # The formatter, opened here for {VERSION} alone: the gemspec reads this file without loading
    # the gem.
    class AIFormatter
      # The semantic version identifier for the gem, used for dependency resolution
      # and enforcing compatibility across upgrades.
      VERSION = '0.11.0'
      public_constant(:VERSION)
    end
  end
end
