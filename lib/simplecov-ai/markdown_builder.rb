# typed: strict
# frozen_string_literal: true

require_relative 'ast_resolver'
require 'time'
require 'stringio'
require_relative 'markdown_builder/snippet_formatter'
require_relative 'markdown_builder/bypass_compiler'
require_relative 'markdown_builder/deficit_grouper'
require_relative 'markdown_builder/branch_enricher'
require_relative 'markdown_builder/deficit_formatter'
require_relative 'markdown_builder/deficit_compiler'

module SimpleCov
  module Formatter
    class AIFormatter
      # Responsible for compiling static text representations from evaluated coverage metrics,
      # optimizing layout size, orchestrating string IO buffers, and halting upon token exhaustion.
      # Serves as the primary mutation boundary to format AI consumption targets.
      class MarkdownBuilder
        extend T::Sig

        # The number of bytes in a kilobyte (metric kB, matching the "kB" unit shown to users)
        BYTES_PER_KB = T.let(1000.0, Float)
        # Text representation for a passed coverage check
        STATUS_PASSED = T.let('PASSED', String)
        # Text representation for a failed coverage check
        STATUS_FAILED = T.let('FAILED', String)
        # Branch-coverage label shown when branch coverage was not enabled for the run
        BRANCH_DISABLED_LABEL = T.let('N/A (branch coverage not enabled)', String)

        # Template for the report header
        HEADER_TEMPLATE = T.let(
          "# AI Coverage Digest\n" \
          "**Status:** %<status>s\n" \
          "**Global Line Coverage:** %<line_pct>s%%\n" \
          "**Global Branch Coverage:** %<branch>s\n" \
          "**Generated At:** %<time>s (Local Timezone)\n",
          String
        )

        # Alert heading for truncated reports
        TRUNCATION_ALERT_HEADING = T.let('> **[WARNING] TRUNCATION NOTIFICATION:**', String)
        # Alert body for truncated reports
        TRUNCATION_ALERT_BODY = T.let(
          '> The total coverage deficit report exceeded the maximum token ' \
          'constraint (%<limit>d kB). ' \
          'The report was truncated. The deficits detailed above represent ' \
          'the lowest-coverage (most critical) files. ' \
          'Please resolve these deficits to reveal the remaining uncovered files in subsequent test runs.',
          String
        )

        # Groups unexecuted lines and branches under their common semantic node.
        class DeficitGroup < T::Struct
          # @return [ASTResolver::SemanticNode, nil] The corresponding structural boundary
          prop :semantic_node, T.nilable(ASTResolver::SemanticNode), default: nil
          # @return [Array<SimpleCov::SourceFile::Line>] The missed source lines
          prop :lines, T::Array[SimpleCov::SourceFile::Line], default: []
          # @return [Array<SimpleCov::SourceFile::Branch>] The missed conditional branches
          prop :branches, T::Array[SimpleCov::SourceFile::Branch], default: []
        end

        # Initializes the Markdown sequence compilation.
        #
        # @param coverage_metrics [SimpleCov::Result] Application-wide coverage aggregation metrics
        # @param config [Configuration] Pre-registered runtime toggles
        sig { params(coverage_metrics: SimpleCov::Result, config: Configuration).void }
        def initialize(coverage_metrics, config)
          @coverage_metrics = T.let(coverage_metrics, SimpleCov::Result)
          @config = T.let(config, Configuration)
          @buffer = T.let(StringIO.new, StringIO)
          @truncated = T.let(false, T::Boolean)
          @ast_cache = T.let({}, T::Hash[String, T.nilable(T::Array[ASTResolver::SemanticNode])])
        end

        # Executes the primary buffer composition logic yielding a monolithic compiled output.
        # Deficits are intrinsically sorted to surface the most crucial test gaps immediately.
        #
        # @return [String] Synthesized string digest of resolved target files and metrics
        sig { returns(String) }
        def build
          write_header
          DeficitCompiler.new(@coverage_metrics, @config, self).write_deficits(@buffer)
          write_truncation_warning if @truncated
          BypassCompiler.new(@coverage_metrics, self).write_bypasses(@buffer) if @config.include_bypasses
          @buffer.string
        end

        sig { params(filename: String).returns(T.nilable(T::Array[ASTResolver::SemanticNode])) }
        def try_resolve_ast(filename)
          return @ast_cache[filename] if @ast_cache.key?(filename)

          @ast_cache[filename] = begin
            ASTResolver.resolve(filename)
          rescue StandardError
            nil
          end
        end

        # Marks the report truncated when the deficit section has exceeded the configured size
        # budget, so the caller can stop emitting further (higher-coverage) files.
        sig { void }
        def record_truncation!
          @truncated = true if @buffer.size / BYTES_PER_KB > @config.max_file_size_kb
        end

        # @return [Boolean] Whether the report has been marked truncated.
        sig { returns(T::Boolean) }
        def truncated?
          @truncated
        end

        private

        # Writes the summary header containing global coverage percentages and generation metadata.
        # Status is PASSED only when line coverage is perfect and, where branch coverage is
        # enabled, branch coverage is perfect too — so a report cannot claim PASSED while listing
        # branch deficits.
        sig { void }
        def write_header
          covered_pct = @coverage_metrics.covered_percent
          branch_pct = branch_coverage_pct
          @buffer.puts format(
            HEADER_TEMPLATE,
            status: compute_status(covered_pct, branch_pct),
            line_pct: covered_pct.round(1),
            branch: branch_pct ? "#{branch_pct.round(1)}%" : BRANCH_DISABLED_LABEL,
            time: Time.now.iso8601
          )
        end

        sig { params(line_pct: Float, branch_pct: T.nilable(Float)).returns(String) }
        def compute_status(line_pct, branch_pct)
          line_perfect = line_pct >= Constants::PERFECT_COVERAGE_PERCENT
          branch_perfect = branch_pct.nil? || branch_pct >= Constants::PERFECT_COVERAGE_PERCENT
          line_perfect && branch_perfect ? STATUS_PASSED : STATUS_FAILED
        end

        # Returns the global branch coverage percentage, or nil when branch coverage was not
        # enabled for the run (so the header can report "N/A" rather than a misleading 100%).
        sig { returns(T.nilable(Float)) }
        def branch_coverage_pct
          return nil unless @coverage_metrics.respond_to?(:covered_branches) &&
                            @coverage_metrics.respond_to?(:total_branches)

          raw_total = @coverage_metrics.total_branches
          return nil if raw_total.nil?

          total = raw_total.to_i
          return Constants::PERFECT_COVERAGE_PERCENT if total.zero?

          @coverage_metrics.covered_branches.to_f / total * Constants::PERFECT_COVERAGE_PERCENT
        end

        # Appends a critical alert if the output hit the token-ceiling constraint and was forcibly terminated.
        sig { void }
        def write_truncation_warning
          @buffer.puts TRUNCATION_ALERT_HEADING
          @buffer.puts format(TRUNCATION_ALERT_BODY, limit: @config.max_file_size_kb)
        end
      end
    end
  end
end
