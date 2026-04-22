# typed: strict
# frozen_string_literal: true

module SimpleCov
  module Formatter
    class AIFormatter
      # Encapsulates all global tuning parameters that dictate the execution size,
      # structure, and output verbosity of the AST-driven Markdown report generator.
      # Exposes strongly-typed attributes through Sorbet to preempt runtime invalidities.
      class Configuration
        extend T::Sig

        # The absolute or relative system path where the final token-efficient markdown
        # document acts as an artifact.
        # @return [String]
        sig { returns(String) }
        attr_accessor :report_path

        # The maximum allowed byte limit to prevent the generation pipeline from overflowing
        # LLM token bounds before terminating the traversal algorithm.
        # @return [Integer]
        attr_accessor :max_file_size_kb

        sig { returns(Integer) }
        attr_accessor :max_snippet_lines

        sig { returns(T::Boolean) }
        attr_accessor :output_to_console

        sig { returns(Symbol) }
        attr_accessor :granularity

        sig { returns(T::Boolean) }
        attr_accessor :include_bypasses

        sig { void }
        def initialize
          @report_path = T.let('coverage/ai_report.md', String)
          @max_file_size_kb = T.let(50, Integer)
          @max_snippet_lines = T.let(5, Integer)
          @output_to_console = T.let(false, T::Boolean)
          @granularity = T.let(:fine, Symbol)
          @include_bypasses = T.let(true, T::Boolean)
        end
      end
    end
  end
end
