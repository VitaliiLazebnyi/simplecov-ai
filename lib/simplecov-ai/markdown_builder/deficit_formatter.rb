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
          BRANCH_DEFICIT_TMPL = T.let('  - **Branch Deficit:** [L%s] Missing coverage for `%s` branch: `%s`', String)

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

            node_deficits.each do |group_key, deficit_group|
              source_lines ||= safe_readlines_proc.call
              format_node_deficit(group_key, deficit_group, source_lines)
            end

            @buffer.puts ''
          end

          private

          sig { params(group_key: String, deficit_group: DeficitGroup, source_lines: T::Array[String]).void }
          def format_node_deficit(group_key, deficit_group, source_lines)
            # Node-backed groups display the semantic name; the group key carries a uniqueness
            # suffix (start line) that must not appear in the report. Node-less groups fall back
            # to their positional key ("Line N" / "Lines N-M").
            display_name = deficit_group.semantic_node&.name || group_key
            @buffer.puts format(NODE_HEADING_TEMPLATE, display_name)

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
              write_branch_snippet(branch, source_lines)
            end
          end

          sig do
            params(line: SimpleCov::SourceFile::Line, source_lines: T::Array[String],
                   node: T.nilable(ASTResolver::SemanticNode)).void
          end
          def write_line_snippet(line, source_lines, node)
            text = sanitize_inline(truncate_snippet(fetch_snippet_text([line.line_number], source_lines),
                                                    @config.max_snippet_lines))
            occurrence_str = calculate_occurrence(line.line_number, source_lines, node)
            @buffer.puts format(LINE_DEFICIT_TMPL, line.line_number, text, occurrence_str).rstrip
          end

          sig { params(branch: SimpleCov::SourceFile::Branch, source_lines: T::Array[String]).void }
          def write_branch_snippet(branch, source_lines)
            raw = extract_branch_text(branch, source_lines)
            text = sanitize_inline(truncate_snippet(raw, @config.max_snippet_lines))
            label = format_branch_label(branch)
            # Each branch already carries a distinct sub-snippet (via column enrichment), so a
            # line-text occurrence count is not meaningful for branches — only for line deficits.
            @buffer.puts format(BRANCH_DEFICIT_TMPL, label, branch.type.to_s, text).rstrip
          end

          sig { params(branch: SimpleCov::SourceFile::Branch).returns(String) }
          def format_branch_label(branch)
            branch.start_line == branch.end_line ? branch.start_line.to_s : "#{branch.start_line}-#{branch.end_line}"
          end
        end
      end
    end
  end
end
