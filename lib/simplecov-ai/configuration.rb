# typed: strong
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
        DEFAULT_REPORT_FILENAME = 'ai_report.md'
        # Default output path of the report: {DEFAULT_REPORT_FILENAME} under SimpleCov's default
        # `coverage_dir` (a custom `coverage_dir` is honoured at format time)
        DEFAULT_REPORT_PATH = "coverage/#{DEFAULT_REPORT_FILENAME}"
        # Default maximum size of the output file in kilobytes
        DEFAULT_MAX_FILE_SIZE_KB = 50
        # Default maximum number of lines for a single snippet
        DEFAULT_MAX_SNIPPET_LINES = 5
        # Default flag for outputting to console
        DEFAULT_OUTPUT_TO_CONSOLE = T.let(false, T::Boolean)
        # Default granularity level of the report
        DEFAULT_GRANULARITY = :fine
        # Default flag for including bypassed regions in the report
        DEFAULT_INCLUDE_BYPASSES = T.let(true, T::Boolean)
        # A value made of whitespace only (or nothing at all).
        BLANK = /\A[[:space:]]*\z/.freeze
        # The set of granularity levels the report generator understands.
        VALID_GRANULARITIES = %i[fine coarse].freeze

        # The values behind the readers. The props check each value's type on assignment
        # (TypeError); the writers of {Configuration} check its domain first. The props declare
        # no `default:` — sorbet-runtime's default machinery fails on JRuby — so
        # {Configuration#initialize} passes every default; the report path is left unset (nil).
        class Settings < T::Struct
          prop :report_path, T.nilable(String)
          prop :max_file_size_kb, Integer
          prop :max_snippet_lines, Integer
          prop :output_to_console, T::Boolean
          prop :granularity, Symbol
          prop :include_bypasses, T::Boolean
        end

        # Domain check shared by the Integer writers.
        #
        # @api private
        # @param name [Symbol] The setting being assigned, named in the error.
        # @param value [Integer] The value to check.
        # @return [Integer] The value, when positive.
        # @raise [ArgumentError] When the value is zero or negative.
        sig { params(name: Symbol, value: Integer).returns(Integer) }
        def self.positive(name, value)
          raise ArgumentError, "#{name} must be a positive Integer, got #{value}" unless value.positive?

          value
        end

        sig { void }
        def initialize
          @settings = T.let(
            Settings.new(max_file_size_kb: DEFAULT_MAX_FILE_SIZE_KB, max_snippet_lines: DEFAULT_MAX_SNIPPET_LINES,
                         output_to_console: DEFAULT_OUTPUT_TO_CONSOLE, granularity: DEFAULT_GRANULARITY,
                         include_bypasses: DEFAULT_INCLUDE_BYPASSES),
            Settings
          )
        end

        # The maximum allowed size, in kilobytes, of the generated report; both the deficit and
        # the bypass section stop at this ceiling so the written file never exceeds it.
        # @return [Integer]
        sig { returns(Integer) }
        def max_file_size_kb
          @settings.max_file_size_kb
        end

        # Limits the number of lines included in code snippets to conserve token usage
        # while maintaining enough structural context for the AI to reason about the logic.
        # @return [Integer]
        sig { returns(Integer) }
        def max_snippet_lines
          @settings.max_snippet_lines
        end

        # Whether the finalized digest is echoed to standard output instead of the one-line
        # "written to" notice, for pipelines that consume the report from STDOUT.
        # @return [Boolean]
        sig { returns(T::Boolean) }
        def output_to_console
          @settings.output_to_console
        end

        # The level of detail in the coverage report (`:fine` for per-line/branch snippets,
        # `:coarse` for a summary line per node).
        # @return [Symbol]
        sig { returns(Symbol) }
        def granularity
          @settings.granularity
        end

        # Whether to include lines skipped via coverage bypass directives (e.g. `:nocov:`),
        # allowing the AI to audit skipped regions for potential testing mandate violations.
        # @return [Boolean]
        sig { returns(T::Boolean) }
        def include_bypasses
          @settings.include_bypasses
        end

        # The destination of the Markdown report. Unless set explicitly this is
        # {DEFAULT_REPORT_FILENAME} inside `SimpleCov.coverage_path`, so a custom `coverage_dir`
        # is honoured; the reader summarises that default as {DEFAULT_REPORT_PATH}. An explicit
        # value is used as-is when absolute and resolved against `SimpleCov.root` otherwise.
        # @return [String]
        sig { returns(String) }
        def report_path
          @settings.report_path || DEFAULT_REPORT_PATH
        end

        # @return [Boolean] Whether report_path was set explicitly rather than left to follow
        #   SimpleCov's coverage directory.
        sig { returns(T::Boolean) }
        def report_path_configured?
          @settings.report_path ? true : false
        end

        # The report's destination: an explicit report_path (absolute as-is, relative against
        # `SimpleCov.root`, so the artifact is stable regardless of the working directory at
        # exit) or, by default, {DEFAULT_REPORT_FILENAME} inside SimpleCov's coverage directory
        # so a custom `coverage_dir` is honoured.
        #
        # @return [String] An absolute filesystem path.
        sig { returns(String) }
        def report_destination
          path = @settings.report_path
          return File.join(SimpleCov.coverage_path, DEFAULT_REPORT_FILENAME) unless path

          Pathname.new(path).absolute? ? path : File.join(SimpleCov.root, path)
        end

        # Every writer enforces its parameter TYPE at runtime (via sorbet-runtime) — a wrongly
        # typed value such as `output_to_console = "yes"` raises TypeError at assignment instead of
        # failing at report time — and the explicit bodies additionally validate the VALUE domain.

        # @param value [String] A non-empty destination path without NUL bytes.
        # @return [void]
        sig { params(value: String).void }
        def report_path=(value)
          raise ArgumentError, 'report_path must not contain a NUL byte' if value.include?("\0")
          raise ArgumentError, 'report_path must not be blank' if value.match?(BLANK)

          @settings.report_path = value
        end

        # @param value [Integer] A positive kilobyte ceiling.
        # @return [void]
        sig { params(value: Integer).void }
        def max_file_size_kb=(value)
          @settings.max_file_size_kb = Configuration.positive(:max_file_size_kb, value)
        end

        # @param value [Integer] A positive snippet-line ceiling.
        # @return [void]
        sig { params(value: Integer).void }
        def max_snippet_lines=(value)
          @settings.max_snippet_lines = Configuration.positive(:max_snippet_lines, value)
        end

        # @param output_to_console [Boolean] Whether to echo the whole digest to STDOUT.
        # @return [void]
        sig { params(output_to_console: T::Boolean).void }
        def output_to_console=(output_to_console)
          @settings.output_to_console = output_to_console
        end

        # @param value [Symbol] One of {VALID_GRANULARITIES}.
        # @return [void]
        sig { params(value: Symbol).void }
        def granularity=(value)
          unless VALID_GRANULARITIES.include?(value)
            raise ArgumentError, "granularity must be one of #{VALID_GRANULARITIES}, got #{value.inspect}"
          end

          @settings.granularity = value
        end

        # @param include_bypasses [Boolean] Whether to audit coverage bypasses.
        # @return [void]
        sig { params(include_bypasses: T::Boolean).void }
        def include_bypasses=(include_bypasses)
          @settings.include_bypasses = include_bypasses
        end
      end
    end
  end
end
