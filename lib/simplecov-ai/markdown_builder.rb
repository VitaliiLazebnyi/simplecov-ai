# typed: strict
# frozen_string_literal: true

module SimpleCov
  module Formatter
    class AIFormatter
      # Responsible for compiling static text representations from evaluated coverage metrics,
      # optimizing layout size, orchestrating string IO buffers, and halting upon token exhaustion.
      # Serves as the primary mutation boundary to format AI consumption targets.
      class MarkdownBuilder
        extend T::Sig

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
        end

        # Executes the primary buffer composition logic yielding a monolithic compiled output.
        # Deficits are intrinsically sorted to surface the most crucial test gaps immediately.
        #
        # @return [String] Synthesized string digest of resolved target files and metrics
        sig { returns(String) }
        def build
          write_header
          write_deficits
          write_bypasses if @config.include_bypasses
          write_truncation_warning if @truncated
          @buffer.string
        end

        private

        sig { void }
        def write_header
          status = @result.covered_percent >= 100.0 ? 'PASSED' : 'FAILED'
          time_str = Time.now.to_s # UI timezone requirement

          @buffer.puts '# AI Coverage Digest'
          @buffer.puts "**Status:** #{status}"
          @buffer.puts "**Global Line Coverage:** #{@result.covered_percent.round(1)}%"

          branch_pct = begin
            @result.covered_branches.to_f / @result.total_branches * 100
          rescue StandardError
            0.0
          end
          @buffer.puts "**Global Branch Coverage:** #{branch_pct.round(1)}%"
          @buffer.puts "**Generated At:** #{time_str}"
          @buffer.puts ''
        end

        sig { void }
        def write_deficits
          @buffer.puts "## Coverage Deficits\n\n"

          # SCMD-REQ-014: Sort by coverage percent ASC, then by filename
          files = @result.files.reject { |f| f.covered_percent >= 100.0 }
                         .sort_by { |f| [f.covered_percent, f.filename] }

          files.each do |file|
            # Check size limits SCMD-REQ-012
            if @buffer.size / 1024.0 > @config.max_file_size_kb
              @truncated = true
              break
            end

            @buffer.puts "### `#{file.project_filename}`"

            begin
              nodes = ASTResolver.resolve(file.filename)
            rescue StandardError => e
              @buffer.puts "- **ERROR:** AST Parsing Failed (`#{e.class}`)"
              next
            end

            process_deficits(file, nodes)
          end
        end

        sig { params(file: SimpleCov::SourceFile, nodes: T::Array[ASTResolver::SemanticNode]).void }
        def process_deficits(file, nodes)
          file.missed_lines.each do |line|
            node = nodes.find { |n| line.line_number >= n.start_line && line.line_number <= n.end_line }
            node_name = node ? node.name : "Line #{line.line_number}"
            @buffer.puts "- `#{node_name}`\n  - **Line Deficit:** Unexecuted code."
          end

          if file.respond_to?(:branches) && file.branches
            file.missed_branches.each do |branch|
              node = nodes.find { |n| branch.start_line >= n.start_line && branch.end_line <= n.end_line }
              node_name = node ? node.name : "Lines #{branch.start_line}-#{branch.end_line}"
              @buffer.puts "- `#{node_name}`\n  - **Branch Deficit:** Missing coverage for conditional."
            end
          end

          @buffer.puts ''
        end

        sig { void }
        def write_bypasses
          has_bypasses = T.let(false, T::Boolean)
          bypass_buffer = StringIO.new

          @result.files.each do |file|
            begin
              nodes = ASTResolver.resolve(file.filename)
            rescue StandardError
              next
            end

            nodes_with_bypasses = nodes.select { |n| n.bypasses.any? }
            next if nodes_with_bypasses.empty?

            has_bypasses = true
            write_file_bypasses(bypass_buffer, file, nodes_with_bypasses)
          end

          return unless has_bypasses

          @buffer.puts "## Ignored Coverage Bypasses\n\n"
          @buffer.puts bypass_buffer.string
        end

        sig { params(buffer: StringIO, file: SimpleCov::SourceFile, bypasses: T::Array[ASTResolver::SemanticNode]).void }
        def write_file_bypasses(buffer, file, bypasses)
          buffer.puts "### `#{file.project_filename}`"
          bypasses.each do |node|
            buffer.puts "- `#{node.name}`\n  - **Bypass Present:** Contains `# :nocov:` directive artificially ignoring coverage."
          end
          buffer.puts ''
        end

        sig { void }
        def write_truncation_warning
          @buffer.puts '> **[WARNING] TRUNCATION NOTIFICATION:**'
          @buffer.puts "> The total coverage deficit report exceeded the maximum token constraint (#{@config.max_file_size_kb} kB). The report was truncated. The deficits detailed above represent the lowest-coverage (most critical) files. Please resolve these deficits to reveal the remaining uncovered files in subsequent test runs."
        end
      end
    end
  end
end
