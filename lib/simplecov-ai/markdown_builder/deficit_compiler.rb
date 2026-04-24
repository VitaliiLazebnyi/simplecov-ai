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

          HEADING = T.let("## Coverage Deficits\n\n", String)
          FILE_HEADING_TEMPLATE = T.let('### `%s`', String)
          ERROR_AST_FAILED = T.let("  - **ERROR:** AST Parsing Failed. Showing raw line numbers instead.\n", String)
          NODE_HEADING_TEMPLATE = T.let('- `%s`', String)
          DEFICIT_COARSE = T.let('  - **Deficit:** Contains unexecuted lines or branches.', String)
          LINE_DEFICIT_TEMPLATE = T.let('  - **Line Deficit:** `%s` %s', String)
          BRANCH_DEFICIT_TEMPLATE = T.let('  - **Branch Deficit:** Missing coverage for conditional `%s` %s', String)

          sig { params(coverage_metrics: SimpleCov::Result, config: Configuration, builder: MarkdownBuilder).void }
          def initialize(coverage_metrics, config, builder)
            @coverage_metrics = coverage_metrics
            @config = config
            @builder = builder
          end

          sig { params(buffer: StringIO).void }
          def write_deficits(buffer)
            files_with_deficits = @coverage_metrics.files.reject { |f| f.covered_percent >= Constants::PERFECT_COVERAGE_PERCENT }
            files = T.let(files_with_deficits.sort_by { |file| [file.covered_percent, file.filename] }, T::Array[SimpleCov::SourceFile])
            return if files.empty?

            buffer.puts HEADING
            files.each do |file|
              break if @builder.truncate_if_needed?

              process_file(buffer, file)
            end
          end

          private

          sig { params(buffer: StringIO, file: SimpleCov::SourceFile).void }
          def process_file(buffer, file)
            buffer.puts format(FILE_HEADING_TEMPLATE, file.project_filename)
            nodes = @builder.try_resolve_ast(file.filename)
            nodes ? process_deficits(buffer, file, nodes) : format_raw_deficits(buffer, file)
          end

          sig { params(buffer: StringIO, file: SimpleCov::SourceFile).void }
          def format_raw_deficits(buffer, file)
            buffer.puts ERROR_AST_FAILED
            deficit_group = MarkdownBuilder::DeficitGroup.new(lines: file.missed_lines, branches: file.missed_branches)
            source = safe_readlines(file.filename)
            format_deficit_group(buffer, deficit_group, source)
            buffer.puts ''
          end

          sig do
            params(buffer: StringIO, file: SimpleCov::SourceFile, nodes: T::Array[ASTResolver::SemanticNode]).void
          end
          def process_deficits(buffer, file, nodes)
            node_deficits = DeficitGrouper.build(file, nodes)
            source_lines = T.let(nil, T.nilable(T::Array[String]))

            node_deficits.each do |node_name, deficit_group|
              break if @builder.truncate_if_needed?

              source_lines ||= safe_readlines(file.filename)
              format_node_deficit(buffer, node_name, deficit_group, source_lines)
            end

            buffer.puts ''
          end

          sig do
            params(buffer: StringIO, node_name: String, deficit_group: DeficitGroup,
                   source_lines: T::Array[String]).void
          end
          def format_node_deficit(buffer, node_name, deficit_group, source_lines)
            buffer.puts format(NODE_HEADING_TEMPLATE, node_name)

            if @config.granularity == :coarse
              buffer.puts DEFICIT_COARSE
            else
              format_deficit_group(buffer, deficit_group, source_lines)
            end
          end

          sig { params(buffer: StringIO, deficit_group: DeficitGroup, source_lines: T::Array[String]).void }
          def format_deficit_group(buffer, deficit_group, source_lines)
            deficit_group.lines.each do |line|
              write_line_snippet(buffer, line, source_lines, deficit_group.semantic_node)
            end

            deficit_group.branches.each do |branch|
              write_branch_snippet(buffer, branch, source_lines, deficit_group.semantic_node)
            end
          end

          sig do
            params(buffer: StringIO, line: SimpleCov::SourceFile::Line, source_lines: T::Array[String],
                   node: T.nilable(ASTResolver::SemanticNode)).void
          end
          def write_line_snippet(buffer, line, source_lines, node)
            text = truncate_snippet(fetch_snippet_text([line.line_number], source_lines), @config.max_snippet_lines)
            occurrence_str = calculate_occurrence(line.line_number, source_lines, node)
            buffer.puts format(LINE_DEFICIT_TEMPLATE, text, occurrence_str).rstrip
          end

          sig do
            params(buffer: StringIO, branch: SimpleCov::SourceFile::Branch, source_lines: T::Array[String],
                   node: T.nilable(ASTResolver::SemanticNode)).void
          end
          def write_branch_snippet(buffer, branch, source_lines, node)
            lines_range = T.cast((branch.start_line..branch.end_line).to_a, T::Array[Integer])
            text = truncate_snippet(fetch_snippet_text(lines_range, source_lines), @config.max_snippet_lines)
            occurrence_str = calculate_occurrence(branch.start_line, source_lines, node)
            buffer.puts format(BRANCH_DEFICIT_TEMPLATE, text, occurrence_str).rstrip
          end

          sig { params(filename: String).returns(T::Array[String]) }
          def safe_readlines(filename)
            File.readlines(filename)
          rescue StandardError
            []
          end
        end
      end
    end
  end
end
