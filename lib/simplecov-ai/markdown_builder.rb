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
          status = T.cast(@result.covered_percent, Float) >= 100.0 ? 'PASSED' : 'FAILED'
          time_str = Time.now.to_s # UI timezone requirement

          @buffer.puts '# AI Coverage Digest'
          @buffer.puts "**Status:** #{status}"
          @buffer.puts "**Global Line Coverage:** #{T.cast(@result.covered_percent, Float).round(1)}%"

          branch_pct = begin
            T.cast(@result.covered_branches, Float) / T.cast(@result.total_branches, Numeric) * 100
          rescue StandardError
            0.0
          end
          @buffer.puts "**Global Branch Coverage:** #{T.cast(branch_pct, Float).round(1)}%"
          @buffer.puts "**Generated At:** #{time_str}"
          @buffer.puts ''
        end

        sig { void }
        def write_deficits
          files_enum = T.cast(@result.files, T::Enumerable[T.untyped])
          files_array = T.let(files_enum.to_a, T::Array[SimpleCov::SourceFile])
          
          # SCMD-REQ-014: Sort by coverage percent ASC, then by filename
          files = T.let(
            files_array.reject { |f| T.cast(f.covered_percent, Float) >= 100.0 }
             .sort_by { |f| [T.cast(f.covered_percent, Float), T.cast(f.filename, String)] },
            T::Array[SimpleCov::SourceFile]
          )

          return if files.empty?

          @buffer.puts "## Coverage Deficits\n\n"

          files.each do |file|
            # Check size limits SCMD-REQ-012
            if @buffer.size / 1024.0 > @config.max_file_size_kb
              @truncated = true
              break
            end

            @buffer.puts "### `#{T.cast(file.project_filename, String)}`"

            begin
              nodes = ASTResolver.resolve(T.cast(file.filename, String))
            rescue StandardError => e
              @buffer.puts "- **ERROR:** AST Parsing Failed (`#{e.class}`)"
              next
            end

            process_deficits(file, nodes)
          end
        end

        sig { params(file: SimpleCov::SourceFile, nodes: T::Array[ASTResolver::SemanticNode]).void }
        def process_deficits(file, nodes)
          T.cast(file.missed_lines, T::Array[SimpleCov::SourceFile::Line]).each do |line|
            line_num = T.cast(line.line_number, Integer)
            node = nodes.find { |n| line_num >= n.start_line && line_num <= n.end_line }
            node_name = node ? node.name : "Line #{line_num}"
            @buffer.puts "- `#{node_name}`\n  - **Line Deficit:** Unexecuted code."
          end

          if file.respond_to?(:branches)
            branches = file.branches
            case branches
            when Array
              if branches.any?
                T.cast(file.missed_branches, T::Array[SimpleCov::SourceFile::Branch]).each do |branch|
                  start_line = T.cast(branch.start_line, Integer)
                  end_line = T.cast(branch.end_line, Integer)
                  node = nodes.find { |n| start_line >= n.start_line && end_line <= n.end_line }
                  node_name = node ? node.name : "Lines #{start_line}-#{end_line}"
                  @buffer.puts "- `#{node_name}`\n  - **Branch Deficit:** Missing coverage for conditional."
                end
              end
            end
          end

          @buffer.puts ''
        end

        sig { void }
        def write_bypasses
          has_bypasses = T.let(false, T::Boolean)
          bypass_buffer = T.let(StringIO.new, StringIO)

          files_enum = T.cast(@result.files, T::Enumerable[T.untyped])
          files_array = T.let(files_enum.to_a, T::Array[SimpleCov::SourceFile])

          files_array.each do |file|
            begin
              nodes = ASTResolver.resolve(T.cast(file.filename, String))
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
