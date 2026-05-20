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
          LINE_DEFICIT_TEMPLATE = T.let('  - **Line Deficit:** [L%d] `%s` %s', String)
          BRANCH_DEFICIT_TEMPLATE = T.let('  - **Branch Deficit:** [L%s] Missing coverage for `%s` branch: `%s` %s',
                                          String)

          sig { params(coverage_metrics: SimpleCov::Result, config: Configuration, builder: MarkdownBuilder).void }
          def initialize(coverage_metrics, config, builder)
            @coverage_metrics = coverage_metrics
            @config = config
            @builder = builder
          end

          sig { params(buffer: StringIO).void }
          def write_deficits(buffer)
            files_with_deficits = @coverage_metrics.files.reject do |f|
              line_perfect = f.covered_percent >= Constants::PERFECT_COVERAGE_PERCENT
              branch_perfect = !f.respond_to?(:branches_coverage_percent) || f.branches_coverage_percent >= Constants::PERFECT_COVERAGE_PERCENT
              line_perfect && branch_perfect
            end
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
            enrich_branch_columns(file)
            buffer.puts format(FILE_HEADING_TEMPLATE, file.project_filename)
            nodes = @builder.try_resolve_ast(file.filename)
            nodes ? process_deficits(buffer, file, nodes) : format_raw_deficits(buffer, file)
          end

          sig { params(file: SimpleCov::SourceFile).void }
          def enrich_branch_columns(file)
            return unless file.respond_to?(:coverage_data)

            coverage_data = file.coverage_data
            return unless coverage_data.is_a?(Hash) && coverage_data['branches']

            raw_branches = coverage_data['branches'].flat_map do |_condition, branches|
              branches.map do |branch_data, _hit_count|
                file.send(:restore_ruby_data_structure, branch_data)
              end
            end

            file.branches.zip(raw_branches).each do |branch, raw|
              next unless raw.is_a?(Array) && raw.size >= 6

              branch.instance_variable_set(:@start_col, raw[3])
              branch.instance_variable_set(:@end_col, raw[5])

              branch.class.send(:attr_reader, :start_col, :end_col) unless branch.respond_to?(:start_col)
            end
          rescue StandardError
            nil
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
            buffer.puts format(LINE_DEFICIT_TEMPLATE, line.line_number, text, occurrence_str).rstrip
          end

          sig do
            params(buffer: StringIO, branch: SimpleCov::SourceFile::Branch, source_lines: T::Array[String],
                   node: T.nilable(ASTResolver::SemanticNode)).void
          end
          def write_branch_snippet(buffer, branch, source_lines, node)
            lines_range = T.cast((branch.start_line..branch.end_line).to_a, T::Array[Integer])

            text = if branch.start_line == branch.end_line && branch.respond_to?(:start_col) && branch.respond_to?(:end_col) && branch.start_col && branch.end_col
                     line_text = source_lines[branch.start_line - 1]
                     if line_text && line_text.length >= branch.end_col
                       line_text[branch.start_col...branch.end_col].to_s.strip
                     else
                       fetch_snippet_text(lines_range, source_lines)
                     end
                   else
                     fetch_snippet_text(lines_range, source_lines)
                   end

            text = truncate_snippet(text, @config.max_snippet_lines)
            occurrence_str = calculate_occurrence(branch.start_line, source_lines, node)
            line_label = branch.start_line == branch.end_line ? branch.start_line.to_s : "#{branch.start_line}-#{branch.end_line}"
            type_label = branch.respond_to?(:type) ? branch.type.to_s : 'conditional'
            buffer.puts format(BRANCH_DEFICIT_TEMPLATE, line_label, type_label, text, occurrence_str).rstrip
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
