# typed: strict
# frozen_string_literal: true

module SimpleCov
  module Formatter
    class AIFormatter
      class MarkdownBuilder
        # Handles the formatting of line and branch deficits into markdown.
        class DeficitFormatter
          extend T::Sig
          include SnippetFormatter

          # Error message for AST parsing failures
          ERROR_AST_FAILED = T.let("  - **ERROR:** AST Parsing Failed. Showing raw line numbers instead.\n", String)
          # Template for node-level deficit headings
          NODE_HEADING_TEMPLATE = T.let('- `%s`', String)
          # Coarse-grained deficit summary message
          DEFICIT_COARSE = T.let('  - **Deficit:** Contains unexecuted lines or branches.', String)
          # Template for a specific line deficit
          LINE_DEFICIT_TMPL = T.let('  - **Line Deficit:** [L%d] `%s` %s', String)
          # Template for a specific branch deficit
          BRANCH_DEFICIT_TMPL = T.let('  - **Branch Deficit:** [L%s] Missing coverage for `%s` branch: `%s` %s', String)

          sig { params(buffer: StringIO, config: Configuration).void }
          def initialize(buffer, config)
            @buffer = buffer
            @config = config
          end

          sig { params(file: SimpleCov::SourceFile, source_lines: T::Array[String]).void }
          def format_raw_deficits(file, source_lines)
            @buffer.puts ERROR_AST_FAILED
            deficit_group = MarkdownBuilder::DeficitGroup.new(lines: file.missed_lines, branches: file.missed_branches)
            format_deficit_group(deficit_group, source_lines)
            @buffer.puts ''
          end

          sig do
            params(file: SimpleCov::SourceFile, nodes: T::Array[ASTResolver::SemanticNode],
                   safe_readlines_proc: T.proc.returns(T::Array[String])).void
          end
          def process_deficits(file, nodes, safe_readlines_proc)
            node_deficits = DeficitGrouper.build(file, nodes)
            source_lines = T.let(nil, T.nilable(T::Array[String]))

            node_deficits.each do |node_name, deficit_group|
              source_lines ||= safe_readlines_proc.call
              format_node_deficit(node_name, deficit_group, source_lines)
            end

            @buffer.puts ''
          end

          private

          sig { params(node_name: String, deficit_group: DeficitGroup, source_lines: T::Array[String]).void }
          def format_node_deficit(node_name, deficit_group, source_lines)
            @buffer.puts format(NODE_HEADING_TEMPLATE, node_name)

            if @config.granularity == :coarse
              @buffer.puts DEFICIT_COARSE
            else
              format_deficit_group(deficit_group, source_lines)
            end
          end

          sig { params(deficit_group: DeficitGroup, source_lines: T::Array[String]).void }
          def format_deficit_group(deficit_group, source_lines)
            deficit_group.lines.each do |line|
              write_line_snippet(line, source_lines, deficit_group.semantic_node)
            end

            deficit_group.branches.each do |branch|
              write_branch_snippet(branch, source_lines, deficit_group.semantic_node)
            end
          end

          sig do
            params(line: SimpleCov::SourceFile::Line, source_lines: T::Array[String],
                   node: T.nilable(ASTResolver::SemanticNode)).void
          end
          def write_line_snippet(line, source_lines, node)
            text = truncate_snippet(fetch_snippet_text([line.line_number], source_lines), @config.max_snippet_lines)
            occurrence_str = calculate_occurrence(line.line_number, source_lines, node)
            @buffer.puts format(LINE_DEFICIT_TMPL, line.line_number, text, occurrence_str).rstrip
          end

          sig do
            params(branch: SimpleCov::SourceFile::Branch, source_lines: T::Array[String],
                   node: T.nilable(ASTResolver::SemanticNode)).void
          end
          def write_branch_snippet(branch, source_lines, node)
            text = truncate_snippet(extract_branch_text(branch, source_lines), @config.max_snippet_lines)
            occurrence = calculate_occurrence(branch.start_line, source_lines, node)
            label = format_branch_label(branch)

            type_val = branch.respond_to?(:type) ? branch.type : nil

            type_label = type_val ? type_val.to_s : 'conditional'
            @buffer.puts format(BRANCH_DEFICIT_TMPL, label, type_label, text, occurrence).rstrip
          end

          sig { params(branch: SimpleCov::SourceFile::Branch).returns(String) }
          def format_branch_label(branch)
            branch.start_line == branch.end_line ? branch.start_line.to_s : "#{branch.start_line}-#{branch.end_line}"
          end

          sig { params(branch: SimpleCov::SourceFile::Branch, source_lines: T::Array[String]).returns(String) }
          def extract_branch_text(branch, source_lines)
            start_col = fetch_column(branch, :start_col)
            end_col = fetch_column(branch, :end_col)

            inline_text = extract_inline_branch(branch, start_col, end_col, source_lines)
            return inline_text if inline_text

            lines_range = T.cast((branch.start_line..branch.end_line).to_a, T::Array[Integer])
            fetch_snippet_text(lines_range, source_lines)
          end

          sig { params(branch: SimpleCov::SourceFile::Branch, col: Symbol).returns(T.nilable(Integer)) }
          def fetch_column(branch, col)
            val = branch.respond_to?(col) ? branch.public_send(col) : branch.instance_variable_get(:"@#{col}")
            T.cast(val, T.nilable(Integer))
          end

          sig do
            params(branch: SimpleCov::SourceFile::Branch, start_col: T.nilable(Integer),
                   end_col: T.nilable(Integer), source_lines: T::Array[String]).returns(T.nilable(String))
          end
          def extract_inline_branch(branch, start_col, end_col, source_lines)
            return nil unless branch.start_line == branch.end_line && start_col && end_col

            line_text = source_lines[branch.start_line - 1]
            return nil unless line_text && line_text.length >= end_col

            line_text[start_col...end_col].to_s.strip
          end
        end
      end
    end
  end
end
