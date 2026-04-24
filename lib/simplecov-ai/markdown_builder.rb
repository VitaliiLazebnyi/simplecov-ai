# typed: strict
# frozen_string_literal: true

require_relative 'ast_resolver'
require 'time'
require_relative 'markdown_builder/snippet_formatter'
require_relative 'markdown_builder/bypass_compiler'
require_relative 'markdown_builder/deficit_grouper'
require_relative 'markdown_builder/deficit_compiler'

module SimpleCov
  module Formatter
    class AIFormatter
      # Responsible for compiling static text representations from evaluated coverage metrics,
      # optimizing layout size, orchestrating string IO buffers, and halting upon token exhaustion.
      # Serves as the primary mutation boundary to format AI consumption targets.
      class MarkdownBuilder
        extend T::Sig
        include SnippetFormatter

        BYTES_PER_KB = T.let(1024.0, Float)
        STATUS_PASSED = T.let('PASSED', String)
        STATUS_FAILED = T.let('FAILED', String)

        HEADER_TEMPLATE = T.let(
          "# AI Coverage Digest\n" \
          "**Status:** %<status>s\n" \
          "**Global Line Coverage:** %<line_pct>s%%\n" \
          "**Global Branch Coverage:** %<branch_pct>s%%\n" \
          "**Generated At:** %<time>s (Local Timezone)\n",
          String
        )

        TRUNCATION_ALERT_HEADING = T.let('> **[WARNING] TRUNCATION NOTIFICATION:**', String)
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
          @file_count = T.let(0, Integer)
          @truncated = T.let(false, T::Boolean)
          @ast_cache = T.let({}, T::Hash[String, T::Array[ASTResolver::SemanticNode]])
        end

        # Executes the primary buffer composition logic yielding a monolithic compiled output.
        # Deficits are intrinsically sorted to surface the most crucial test gaps immediately.
        #
        # @return [String] Synthesized string digest of resolved target files and metrics
        sig { returns(String) }
        def build
          write_header
          DeficitCompiler.new(@coverage_metrics, @config, self).write_deficits(@buffer)
          BypassCompiler.new(@coverage_metrics, self).write_bypasses(@buffer) if @config.include_bypasses
          write_truncation_warning if @truncated
          @buffer.string
        end

        sig { params(filename: String).returns(T.nilable(T::Array[ASTResolver::SemanticNode])) }
        def try_resolve_ast(filename)
          @ast_cache[filename] ||= ASTResolver.resolve(filename)
        rescue StandardError
          nil
        end

        sig { returns(T::Boolean) }
        def truncate_if_needed?
          return false unless @buffer.size / BYTES_PER_KB > @config.max_file_size_kb

          @truncated = true
          true
        end

        private

        # Writes the summary header containing global coverage percentages and generation metadata.
        sig { void }
        def write_header
          covered_pct = @coverage_metrics.covered_percent
          status = covered_pct >= Constants::PERFECT_COVERAGE_PERCENT ? STATUS_PASSED : STATUS_FAILED
          @buffer.puts format(
            HEADER_TEMPLATE,
            status: status,
            line_pct: covered_pct.round(1),
            branch_pct: calculate_branch_pct.round(1),
            time: Time.now.iso8601
          )
        end

        sig { returns(Float) }
        def calculate_branch_pct
          unless @coverage_metrics.respond_to?(:covered_branches) &&
                 @coverage_metrics.respond_to?(:total_branches)
            return 0.0
          end

          total = @coverage_metrics.total_branches
          return 0.0 if total.to_i.zero?

          covered = @coverage_metrics.covered_branches
          covered.to_f / total * Constants::PERFECT_COVERAGE_PERCENT
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
