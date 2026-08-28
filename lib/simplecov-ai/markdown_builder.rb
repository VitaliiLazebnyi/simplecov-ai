# typed: strict
# frozen_string_literal: true

require_relative 'ast_resolver'
require 'time'
require 'stringio'
require_relative 'markdown_builder/decode_guard'
require_relative 'markdown_builder/inline_code'
require_relative 'markdown_builder/source_lines'
require_relative 'markdown_builder/report_budget'
require_relative 'markdown_builder/section_writer'
require_relative 'markdown_builder/deficit_group'
require_relative 'markdown_builder/snippet_formatter'
require_relative 'markdown_builder/skip_regions'
require_relative 'markdown_builder/bypass_compiler'
require_relative 'markdown_builder/deficit_grouper'
require_relative 'markdown_builder/branch_enricher'
require_relative 'markdown_builder/deficit_formatter'
require_relative 'markdown_builder/deficit_compiler'

module SimpleCov
  module Formatter
    class AIFormatter
      # Responsible for compiling static text representations from evaluated coverage metrics:
      # the telemetry header, the deficit and bypass sections written through a single size
      # budget, and the closing truncation notice when that budget ran out.
      class MarkdownBuilder
        extend T::Sig

        # Text representation for a passed coverage check
        STATUS_PASSED = T.let('PASSED', String)
        # Text representation for a failed coverage check
        STATUS_FAILED = T.let('FAILED', String)
        # Line-coverage label shown when line coverage was not enabled for the run (SimpleCov
        # >= 1.0 allows a branch- or method-only run)
        LINE_DISABLED_LABEL = T.let('N/A (line coverage not enabled)', String)
        # Branch-coverage label shown when branch coverage was not enabled for the run
        BRANCH_DISABLED_LABEL = T.let('N/A (branch coverage not enabled)', String)
        # Label shown for a figure SimpleCov could not compute from a corrupt resultset
        UNDECODABLE_LABEL = T.let('N/A (coverage data could not be decoded)', String)
        # Stands in for a figure SimpleCov raised on while decoding: not a number, so it never
        # compares as perfect and the status reads FAILED
        UNDECODABLE_PERCENT = T.let(Float::NAN, Float)
        # Percentages are printed with one decimal, floored (see #figure_label)
        PERCENT_TEMPLATE = T.let('%.1f%%', String)

        # Template for the report header; the method line is empty unless SimpleCov measured
        # method coverage, keeping the header byte-identical for every other run.
        HEADER_TEMPLATE = T.let(
          "# AI Coverage Digest\n" \
          "**Status:** %<status>s\n" \
          "**Global Line Coverage:** %<line>s\n" \
          "**Global Branch Coverage:** %<branch>s\n" \
          '%<method_line>s' \
          "**Generated At:** %<time>s (Local Timezone)\n",
          String
        )
        # Header line for SimpleCov >= 1.0 method coverage (`enable_coverage :method`)
        METHOD_COVERAGE_LINE = T.let("**Global Method Coverage:** %<method>s\n", String)

        # Initializes the Markdown sequence compilation.
        #
        # @param coverage_metrics [SimpleCov::Result] Application-wide coverage aggregation metrics
        # @param config [Configuration] Pre-registered runtime toggles
        sig { params(coverage_metrics: SimpleCov::Result, config: Configuration).void }
        def initialize(coverage_metrics, config)
          @coverage_metrics = T.let(coverage_metrics, SimpleCov::Result)
          @config = T.let(config, Configuration)
          @buffer = T.let(StringIO.new, StringIO)
          @ast_cache = T.let({}, T::Hash[String, T.nilable(T::Array[ASTResolver::SemanticNode])])
        end

        # Executes the primary buffer composition logic yielding a monolithic compiled output.
        # Deficits are intrinsically sorted to surface the most crucial test gaps immediately,
        # and both sections stop at the configured size ceiling.
        #
        # @return [String] Synthesized string digest of resolved target files and metrics
        sig { returns(String) }
        def build
          budget = ReportBudget.new(@buffer, @config.max_file_size_kb, @coverage_metrics.files.size)
          budget.write(header)
          omitted_deficit_files = DeficitCompiler.new(@coverage_metrics, @config, self).write_deficits(budget)
          omitted_bypass_files = write_bypasses(budget)
          if omitted_deficit_files.positive? || omitted_bypass_files.positive?
            budget.write_notice(omitted_deficit_files, omitted_bypass_files)
          end
          @buffer.string
        end

        # Resolves (once per file, per SCAI-REQ-020) the semantic nodes of a source file.
        #
        # @param filename [String] The absolute path of the file.
        # @return [Array<ASTResolver::SemanticNode>, nil] The nodes, or nil when resolution failed.
        sig { params(filename: String).returns(T.nilable(T::Array[ASTResolver::SemanticNode])) }
        def try_resolve_ast(filename)
          @ast_cache.fetch(filename) { @ast_cache[filename] = resolve_nodes(filename) }
        end

        private

        sig { params(filename: String).returns(T.nilable(T::Array[ASTResolver::SemanticNode])) }
        def resolve_nodes(filename)
          ASTResolver.resolve(filename)
        rescue StandardError
          nil
        end

        sig { params(budget: ReportBudget).returns(Integer) }
        def write_bypasses(budget)
          return 0 unless @config.include_bypasses

          BypassCompiler.new(@coverage_metrics, self).write_bypasses(budget)
        end

        # The summary header: global percentages and generation metadata. Status is PASSED only
        # when every criterion SimpleCov measured (lines, branches, methods) is perfect, so a
        # report cannot claim PASSED while listing deficits of any kind. Each figure is read
        # through the decode guard: SimpleCov computes its statistics for every criterion at
        # once, so one corrupt branch descriptor makes every figure undecodable.
        sig { returns(String) }
        def header
          line_pct = DecodeGuard.attempt(UNDECODABLE_PERCENT) { @coverage_metrics.covered_percent }
          branch_pct = DecodeGuard.attempt(UNDECODABLE_PERCENT) { branch_coverage_pct }
          method_pct = DecodeGuard.attempt(UNDECODABLE_PERCENT) { method_coverage_pct }
          method_label = figure_label(method_pct)
          format(HEADER_TEMPLATE,
                 status: compute_status([line_pct, branch_pct, method_pct]),
                 line: figure_label(line_pct) || LINE_DISABLED_LABEL,
                 branch: figure_label(branch_pct) || BRANCH_DISABLED_LABEL,
                 method_line: method_label && format(METHOD_COVERAGE_LINE, method: method_label),
                 time: Time.now.iso8601)
        end

        # An unmeasured criterion (nil) does not fail the run; an undecodable one ({UNDECODABLE_PERCENT},
        # NaN) compares as imperfect, so it does.
        sig { params(percentages: T::Array[T.nilable(Float)]).returns(String) }
        def compute_status(percentages)
          perfect = percentages.all? { |percent| percent.nil? || percent >= Constants::PERFECT_COVERAGE_PERCENT }
          perfect ? STATUS_PASSED : STATUS_FAILED
        end

        # One floored decimal, so a run at 99.96% never reads as 100.0% beside a FAILED status;
        # {UNDECODABLE_LABEL} for a figure SimpleCov could not compute; nil for an unmeasured one.
        sig { params(percent: T.nilable(Float)).returns(T.nilable(String)) }
        def figure_label(percent)
          return nil if percent.nil?

          percent.nan? ? UNDECODABLE_LABEL : format(PERCENT_TEMPLATE, percent.floor(1))
        end

        # Global branch coverage, or nil when branch coverage was not enabled for the run (so
        # the header can report "N/A" rather than a misleading 100%).
        sig { returns(T.nilable(Float)) }
        def branch_coverage_pct
          coverage_ratio(@coverage_metrics.covered_branches, @coverage_metrics.total_branches)
        end

        # Global method coverage, or nil unless SimpleCov (>= 1.0, `enable_coverage :method`)
        # measured methods in this run.
        sig { returns(T.nilable(Float)) }
        def method_coverage_pct
          return nil unless MethodDeficit.measured?(@coverage_metrics)

          coverage_ratio(@coverage_metrics.covered_methods, @coverage_metrics.total_methods)
        end

        sig { params(covered: T.nilable(Integer), total: T.nilable(Integer)).returns(T.nilable(Float)) }
        def coverage_ratio(covered, total)
          return nil if total.nil?
          return Constants::PERFECT_COVERAGE_PERCENT if total.zero?

          covered.to_f / total * Constants::PERFECT_COVERAGE_PERCENT
        end
      end
    end
  end
end
