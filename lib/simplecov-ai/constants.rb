# typed: strict
# frozen_string_literal: true

module SimpleCov
  module Formatter
    class AIFormatter
      # Houses globally shared constant values utilized across the AI formatter suite
      # to prevent magic string duplication and establish a single source of truth.
      module Constants
        extend T::Sig

        # The explicit value used to designate a file or coverage block as perfectly covered.
        PERFECT_COVERAGE_PERCENT = T.let(100.0, Float)

        # The directive typically employed within comments to force coverage engines to bypass execution tracking.
        NOCOV_DIRECTIVE = T.let(':nocov:', String)
      end
    end
  end
end
