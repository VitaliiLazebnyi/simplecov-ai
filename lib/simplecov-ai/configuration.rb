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

        DEFAULT_REPORT_PATH = T.let('coverage/ai_report.md', String)
        DEFAULT_MAX_FILE_SIZE_KB = T.let(50, Integer)
        DEFAULT_MAX_SNIPPET_LINES = T.let(5, Integer)
        DEFAULT_OUTPUT_TO_CONSOLE = T.let(false, T::Boolean)
        DEFAULT_GRANULARITY = T.let(:fine, Symbol)
        DEFAULT_INCLUDE_BYPASSES = T.let(true, T::Boolean)

        # The absolute or relative system path where the final token-efficient markdown
        # document acts as an artifact.
        # @return [String]
        sig { returns(String) }
        attr_accessor :report_path

        # The maximum allowed byte limit to prevent the generation pipeline from overflowing
        # LLM token bounds before terminating the traversal algorithm.
        # @return [Integer]
        sig { returns(Integer) }
        attr_accessor :max_file_size_kb

        # Limits the number of lines included in code snippets to conserve token usage
        # while maintaining enough structural context for the AI to reason about the logic.
        sig { returns(Integer) }
        attr_accessor :max_snippet_lines

        # Determines whether the generated markdown report is printed directly to standard output,
        # facilitating pipeline integrations where artifacts are piped rather than read from disk.
        sig { returns(T::Boolean) }
        attr_accessor :output_to_console

        # Specifies the level of detail in the coverage report (e.g., :fine, :coarse)
        # to balance between comprehensive reporting and strict token constraints.
        sig { returns(Symbol) }
        attr_accessor :granularity

        # Controls whether to include lines skipped via coverage bypass directives (e.g., :nocov:),
        # allowing the AI to audit skipped regions for potential testing mandate violations.
        sig { returns(T::Boolean) }
        attr_accessor :include_bypasses

        sig { void }
        def initialize
          @report_path = T.let(DEFAULT_REPORT_PATH, String)
          @max_file_size_kb = T.let(DEFAULT_MAX_FILE_SIZE_KB, Integer)
          @max_snippet_lines = T.let(DEFAULT_MAX_SNIPPET_LINES, Integer)
          @output_to_console = T.let(DEFAULT_OUTPUT_TO_CONSOLE, T::Boolean)
          @granularity = T.let(DEFAULT_GRANULARITY, Symbol)
          @include_bypasses = T.let(DEFAULT_INCLUDE_BYPASSES, T::Boolean)
        end
      end
    end
  end
end
