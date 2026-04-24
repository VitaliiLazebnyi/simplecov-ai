# typed: strict
# frozen_string_literal: true

module SimpleCov
  module Formatter
    class AIFormatter
      class MarkdownBuilder
        # Iterates through files with coverage deficits and coordinates their AST parsing and snippet generation.
        class DeficitCompiler
          extend T::Sig
          include SnippetFormatter

          sig { params(result: SimpleCov::Result, config: Configuration, builder: MarkdownBuilder).void }
          def initialize(result, config, builder)
            @result = result
            @config = config
            @builder = builder
          end

          sig { params(buffer: StringIO).void }
          def write_deficits(buffer)
            files = T.let(
              @result.files.reject { |f| f.covered_percent >= 100.0 }.sort_by { |f| [f.covered_percent, f.filename] },
              T::Array[SimpleCov::SourceFile]
            )
            return if files.empty?

            buffer.puts "## Coverage Deficits\n\n"
            files.each do |file|
              break if @builder.truncate_if_needed?

              process_file(buffer, file)
            end
          end

          private

          sig { params(buffer: StringIO, file: SimpleCov::SourceFile).void }
          def process_file(buffer, file)
            buffer.puts "### `#{file.project_filename}`"
            nodes = @builder.try_resolve_ast(file.filename)
            nodes ? process_deficits(buffer, file, nodes) : format_raw_deficits(buffer, file)
          end

          sig { params(buffer: StringIO, file: SimpleCov::SourceFile).void }
          def format_raw_deficits(buffer, file)
            buffer.puts "  - **ERROR:** AST Parsing Failed. Showing raw line numbers instead.\n"
            group = MarkdownBuilder::DeficitGroup.new(
              lines: file.missed_lines,
              branches: file.missed_branches
            )
            format_deficit_group(buffer, group, fetch_source_lines(file.filename))
            buffer.puts ''
          end

          sig do
            params(buffer: StringIO, file: SimpleCov::SourceFile, nodes: T::Array[ASTResolver::SemanticNode]).void
          end
          def process_deficits(buffer, file, nodes)
            node_deficits = DeficitGrouper.build(file, nodes)
            source_lines = T.let(nil, T.nilable(T::Array[String]))

            node_deficits.each do |node_name, group|
              break if @builder.truncate_if_needed?

              source_lines ||= fetch_source_lines(file.filename)
              format_node_deficit(buffer, node_name, group, source_lines)
            end

            buffer.puts ''
          end

          sig { params(buffer: StringIO, node_name: String, group: DeficitGroup, source_lines: T::Array[String]).void }
          def format_node_deficit(buffer, node_name, group, source_lines)
            buffer.puts "- `#{node_name}`"

            if @config.granularity == :coarse
              buffer.puts '  - **Deficit:** Contains unexecuted lines or branches.'
            else
              format_deficit_group(buffer, group, source_lines)
            end
          end

          sig { params(filename: String).returns(T::Array[String]) }
          def fetch_source_lines(filename)
            File.readlines(filename)
          rescue StandardError
            []
          end

          sig { params(buffer: StringIO, group: DeficitGroup, source_lines: T::Array[String]).void }
          def format_deficit_group(buffer, group, source_lines)
            group.lines.each do |line|
              write_line_snippet(buffer, line, source_lines, group.semantic_node)
            end

            group.branches.each do |branch|
              write_branch_snippet(buffer, branch, source_lines, group.semantic_node)
            end
          end

          sig do
            params(buffer: StringIO, line: SimpleCov::SourceFile::Line, source_lines: T::Array[String],
                   node: T.nilable(ASTResolver::SemanticNode)).void
          end
          def write_line_snippet(buffer, line, source_lines, node)
            line_num = line.line_number
            text = truncate_snippet(fetch_snippet_text([line_num], source_lines), @config.max_snippet_lines)
            occurrence_str = calculate_occurrence(line_num, source_lines, node)
            buffer.puts "  - **Line Deficit:** `#{text}` #{occurrence_str}".rstrip
          end

          sig do
            params(buffer: StringIO, branch: SimpleCov::SourceFile::Branch, source_lines: T::Array[String],
                   node: T.nilable(ASTResolver::SemanticNode)).void
          end
          def write_branch_snippet(buffer, branch, source_lines, node)
            start_line = branch.start_line
            end_line = branch.end_line
            lines_range = T.cast((start_line..end_line).to_a, T::Array[Integer])
            text = truncate_snippet(fetch_snippet_text(lines_range, source_lines), @config.max_snippet_lines)
            occurrence_str = calculate_occurrence(start_line, source_lines, node)
            buffer.puts "  - **Branch Deficit:** Missing coverage for conditional `#{text}` #{occurrence_str}".rstrip
          end
        end
      end
    end
  end
end
