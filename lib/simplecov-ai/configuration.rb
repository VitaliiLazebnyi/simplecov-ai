# typed: strict
# frozen_string_literal: true

module SimpleCov
  module Formatter
    class AIFormatter
      # Encapsulates all global tuning parameters that dictate the execution size,
      # structure, and output verbosity of the AST-driven Markdown report generator.
      # Each attribute is validated on assignment so misconfiguration fails immediately at
      # the point of the invalid write rather than deep inside coverage processing at exit.
      class Configuration
        extend T::Sig

        # File name of the report inside SimpleCov's coverage directory when no report_path is set
        DEFAULT_REPORT_FILENAME = T.let('ai_report.md', String)
        # Default output path of the report: {DEFAULT_REPORT_FILENAME} under SimpleCov's default
        # `coverage_dir` (a custom `coverage_dir` is honoured at format time)
        DEFAULT_REPORT_PATH = T.let("coverage/#{DEFAULT_REPORT_FILENAME}", String)
        # Default maximum size of the output file in kilobytes
        DEFAULT_MAX_FILE_SIZE_KB = T.let(50, Integer)
        # Default maximum number of lines for a single snippet
        DEFAULT_MAX_SNIPPET_LINES = T.let(5, Integer)
        # Default flag for outputting to console
        DEFAULT_OUTPUT_TO_CONSOLE = T.let(false, T::Boolean)
        # Default granularity level of the report
        DEFAULT_GRANULARITY = T.let(:fine, Symbol)
        # Default flag for including bypassed regions in the report
        DEFAULT_INCLUDE_BYPASSES = T.let(true, T::Boolean)
        # The set of granularity levels the report generator understands.
        VALID_GRANULARITIES = T.let(%i[fine coarse].freeze, T::Array[Symbol])

        # The maximum allowed size, in kilobytes, of the generated report; both the deficit and
        # the bypass section stop at this ceiling so the written file never exceeds it.
        # @return [Integer]
        sig { returns(Integer) }
        attr_reader :max_file_size_kb

        # Limits the number of lines included in code snippets to conserve token usage
        # while maintaining enough structural context for the AI to reason about the logic.
        # @return [Integer]
        sig { returns(Integer) }
        attr_reader :max_snippet_lines

        # Whether the finalized digest is echoed to standard output instead of the one-line
        # "written to" notice, for pipelines that consume the report from STDOUT.
        # @return [Boolean]
        sig { returns(T::Boolean) }
        attr_reader :output_to_console

        # The level of detail in the coverage report (`:fine` for per-line/branch snippets,
        # `:coarse` for a summary line per node).
        # @return [Symbol]
        sig { returns(Symbol) }
        attr_reader :granularity

        # Whether to include lines skipped via coverage bypass directives (e.g. `:nocov:`),
        # allowing the AI to audit skipped regions for potential testing mandate violations.
        # @return [Boolean]
        sig { returns(T::Boolean) }
        attr_reader :include_bypasses

        sig { void }
        def initialize
          @report_path = T.let(nil, T.nilable(String))
          @max_file_size_kb = T.let(DEFAULT_MAX_FILE_SIZE_KB, Integer)
          @max_snippet_lines = T.let(DEFAULT_MAX_SNIPPET_LINES, Integer)
          @output_to_console = T.let(DEFAULT_OUTPUT_TO_CONSOLE, T::Boolean)
          @granularity = T.let(DEFAULT_GRANULARITY, Symbol)
          @include_bypasses = T.let(DEFAULT_INCLUDE_BYPASSES, T::Boolean)
        end

        # The destination of the Markdown report. Unless set explicitly this is
        # {DEFAULT_REPORT_FILENAME} inside `SimpleCov.coverage_path`, so a custom `coverage_dir`
        # is honoured; the reader summarises that default as {DEFAULT_REPORT_PATH}. An explicit
        # value is used as-is when absolute and resolved against `SimpleCov.root` otherwise.
        # @return [String]
        sig { returns(String) }
        def report_path
          @report_path || DEFAULT_REPORT_PATH
        end

        # @return [Boolean] Whether report_path was set explicitly rather than left to follow
        #   SimpleCov's coverage directory.
        sig { returns(T::Boolean) }
        def report_path_configured?
          !@report_path.nil?
        end

        # Every writer enforces its parameter TYPE at runtime (via sorbet-runtime) — a wrongly
        # typed value such as `output_to_console = "yes"` raises TypeError at assignment instead of
        # failing at report time — and the explicit bodies additionally validate the VALUE domain.

        # @param value [String] A non-empty destination path without NUL bytes.
        # @return [void]
        sig { params(value: String).void }
        def report_path=(value)
          raise ArgumentError, 'report_path must not contain a NUL byte' if value.include?("\0")
          raise ArgumentError, 'report_path must not be blank' if value.strip.empty?

          @report_path = value
        end

        # @param value [Integer] A positive kilobyte ceiling.
        # @return [void]
        sig { params(value: Integer).void }
        def max_file_size_kb=(value)
          @max_file_size_kb = validate_positive(:max_file_size_kb, value)
        end

        # @param value [Integer] A positive snippet-line ceiling.
        # @return [void]
        sig { params(value: Integer).void }
        def max_snippet_lines=(value)
          @max_snippet_lines = validate_positive(:max_snippet_lines, value)
        end

        # @param output_to_console [Boolean] Whether to echo the whole digest to STDOUT.
        # @return [Boolean]
        sig { params(output_to_console: T::Boolean).returns(T::Boolean) }
        attr_writer :output_to_console

        # @param value [Symbol] One of {VALID_GRANULARITIES}.
        # @return [void]
        sig { params(value: Symbol).void }
        def granularity=(value)
          unless VALID_GRANULARITIES.include?(value)
            raise ArgumentError, "granularity must be one of #{VALID_GRANULARITIES.inspect}, got #{value.inspect}"
          end

          @granularity = value
        end

        # @param include_bypasses [Boolean] Whether to audit coverage bypasses.
        # @return [Boolean]
        sig { params(include_bypasses: T::Boolean).returns(T::Boolean) }
        attr_writer :include_bypasses

        private

        sig { params(name: Symbol, value: Integer).returns(Integer) }
        def validate_positive(name, value)
          raise ArgumentError, "#{name} must be a positive Integer, got #{value.inspect}" unless value.positive?

          value
        end
      end
    end
  end
end
