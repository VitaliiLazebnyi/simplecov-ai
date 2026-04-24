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
        # @param result [SimpleCov::Result] Application-wide coverage aggregation metrics
        # @param config [Configuration] Pre-registered runtime toggles
        sig { params(result: SimpleCov::Result, config: Configuration).void }
        def initialize(result, config)
          @result = T.let(result, SimpleCov::Result)
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
          DeficitCompiler.new(@result, @config, self).write_deficits(@buffer)
          BypassCompiler.new(@result, self).write_bypasses(@buffer) if @config.include_bypasses
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
          return false unless @buffer.size / 1024.0 > @config.max_file_size_kb

          @truncated = true
          true
        end

        private

        # Writes the summary header containing global coverage percentages and generation metadata.
        sig { void }
        def write_header
          status = @result.covered_percent >= 100.0 ? 'PASSED' : 'FAILED'
          @buffer.puts '# AI Coverage Digest'
          @buffer.puts "**Status:** #{status}"
          @buffer.puts "**Global Line Coverage:** #{@result.covered_percent.round(1)}%"
          @buffer.puts "**Global Branch Coverage:** #{calculate_branch_pct.round(1)}%"
          @buffer.puts "**Generated At:** #{Time.now.iso8601} (Local Timezone)"
          @buffer.puts ''
        end

        sig { returns(Float) }
        def calculate_branch_pct
          return 0.0 unless @result.respond_to?(:covered_branches) && @result.respond_to?(:total_branches)

          total = @result.total_branches
          return 0.0 if total.to_i.zero?

          covered = @result.covered_branches
          covered.to_f / total * 100.0
        end

        # Appends a critical alert if the output hit the token-ceiling constraint and was forcibly terminated.
        sig { void }
        def write_truncation_warning
          @buffer.puts '> **[WARNING] TRUNCATION NOTIFICATION:**'
          msg = '> The total coverage deficit report exceeded the maximum token ' \
                "constraint (#{@config.max_file_size_kb} kB). " \
                'The report was truncated. The deficits detailed above represent ' \
                'the lowest-coverage (most critical) files. ' \
                'Please resolve these deficits to reveal the remaining uncovered files in subsequent test runs.'
          @buffer.puts msg
        end
      end
    end
  end
end
