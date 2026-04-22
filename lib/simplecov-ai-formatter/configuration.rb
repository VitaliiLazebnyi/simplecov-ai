# typed: strict
# frozen_string_literal: true

module SimpleCov
  module Formatter
    class AIFormatter
      class Configuration
        extend T::Sig

        sig { returns(String) }
        attr_accessor :report_path

        sig { returns(Integer) }
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
