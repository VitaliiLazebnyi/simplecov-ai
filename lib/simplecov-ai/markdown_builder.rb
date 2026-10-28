# typed: strong
# frozen_string_literal: true

require_relative 'ast_resolver'
require 'time'
require 'stringio'
require_relative 'markdown_builder/decode_guard'
require_relative 'markdown_builder/inline_code'
require_relative 'markdown_builder/source_lines'
require_relative 'markdown_builder/report_budget'
require_relative 'markdown_builder/figure'
require_relative 'markdown_builder/header'
require_relative 'markdown_builder/section_writer'
require_relative 'markdown_builder/deficit_group'
require_relative 'markdown_builder/snippet_formatter'
require_relative 'markdown_builder/skip_regions'
require_relative 'markdown_builder/bypass_compiler'
require_relative 'markdown_builder/deficit_grouper'
require_relative 'markdown_builder/branch_enricher'
require_relative 'markdown_builder/deficit_lines'
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

        # Initializes the Markdown sequence compilation.
        #
        # @param coverage_metrics [SimpleCov::Result] Application-wide coverage aggregation metrics
        # @param config [Configuration] Pre-registered runtime toggles
        sig { params(coverage_metrics: SimpleCov::Result, config: Configuration).void }
        def initialize(coverage_metrics, config)
          @coverage_metrics = coverage_metrics
          @config = config
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
          budget.write(Header.new(@coverage_metrics).render)
          budget.write_notice(DeficitCompiler.new(@coverage_metrics, @config, self).write_deficits(budget),
                              write_bypasses(budget))
          @buffer.string
        end

        # Resolves (once per file, per SCAI-REQ-020) the semantic nodes of a source file.
        #
        # @param filename [String] The absolute path of the file.
        # @return [Array<ASTResolver::SemanticNode>, nil] The nodes, or nil when resolution failed.
        sig { params(filename: String).returns(T.nilable(T::Array[ASTResolver::SemanticNode])) }
        def try_resolve_ast(filename)
          @ast_cache.fetch(filename) { @ast_cache[filename] = ASTResolver.try_resolve(filename) }
        end

        private

        sig { params(budget: ReportBudget).returns(Integer) }
        def write_bypasses(budget)
          return 0 unless @config.include_bypasses

          BypassCompiler.new(@coverage_metrics, self).write_bypasses(budget)
        end
      end
    end
  end
end
