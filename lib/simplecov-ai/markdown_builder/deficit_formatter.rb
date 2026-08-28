# typed: strict
# frozen_string_literal: true

module SimpleCov
  module Formatter
    class AIFormatter
      class MarkdownBuilder
        # Renders the deficits of one file as Markdown fragments, one per semantic node group.
        class DeficitFormatter
          extend T::Sig
          include SnippetFormatter

          # Error message for AST parsing failures
          ERROR_AST_FAILED = T.let('  - **ERROR:** AST Parsing Failed. Showing raw line numbers instead.', String)
          # Template for node-level deficit headings
          NODE_HEADING_TEMPLATE = T.let('- %s', String)
          # Coarse-grained deficit summary message
          DEFICIT_COARSE = T.let('  - **Deficit:** Contains unexecuted lines or branches.', String)
          # Template for a specific line deficit
          LINE_DEFICIT_TMPL = T.let('  - **Line Deficit:** [L%d] %s %s', String)
          # Template for a specific branch deficit
          BRANCH_DEFICIT_TMPL = T.let('  - **Branch Deficit:** [L%s] Missing coverage for %s branch: %s', String)
          # Template for a method SimpleCov's method coverage reported as never invoked
          METHOD_DEFICIT_TMPL = T.let('  - **Method Deficit:** [L%s] %s never invoked', String)

          # @param config [Configuration] The runtime toggles (granularity, snippet limits).
          # @param source_lines [Array<String>] The file's source, for snippets.
          # @param branch_columns [Hash] The branch column map from {BranchEnricher}.
          sig do
            params(config: Configuration, source_lines: T::Array[String], branch_columns: BranchEnricher::ColumnMap).void
          end
          def initialize(config, source_lines, branch_columns)
            @config = config
            @source_lines = source_lines
            @branch_columns = branch_columns
          end

          # @param file [SimpleCov::SourceFile] The file with deficits.
          # @param nodes [Array<ASTResolver::SemanticNode>] The file's resolved nodes.
          # @param method_deficits [Array<MethodDeficit>] The file's never-invoked methods.
          # @return [Array<String>] One fragment per semantic node group, in source order.
          sig do
            params(file: SimpleCov::SourceFile, nodes: T::Array[ASTResolver::SemanticNode],
                   method_deficits: T::Array[MethodDeficit]).returns(T::Array[String])
          end
          def render_node_fragments(file, nodes, method_deficits)
            DeficitGrouper.build(file, nodes, method_deficits).map do |group_key, deficit_group|
              # Node-backed groups display the semantic name; the group key carries a uniqueness
              # suffix (start line) that must not appear in the report. Node-less groups fall
              # back to their positional key ("Line N" / "Lines N-M").
              render_group(deficit_group.semantic_node&.name || group_key, deficit_group)
            end
          end

          # @param file [SimpleCov::SourceFile] The file whose AST could not be resolved.
          # @param method_deficits [Array<MethodDeficit>] The file's never-invoked methods.
          # @return [Array<String>] A single fragment: the parse-failure notice followed by
          #   every deficit under its raw line numbers.
          sig { params(file: SimpleCov::SourceFile, method_deficits: T::Array[MethodDeficit]).returns(T::Array[String]) }
          def render_raw_fragments(file, method_deficits)
            [fragment([ERROR_AST_FAILED] + deficit_lines(DeficitGrouper.raw_group(file, method_deficits)))]
          end

          private

          sig { params(display_name: String, deficit_group: DeficitGroup).returns(String) }
          def render_group(display_name, deficit_group)
            heading = format(NODE_HEADING_TEMPLATE, InlineCode.span(display_name))
            body = @config.granularity == :coarse ? [DEFICIT_COARSE] : deficit_lines(deficit_group)
            fragment([heading] + body)
          end

          sig { params(markdown_lines: T::Array[String]).returns(String) }
          def fragment(markdown_lines)
            "#{markdown_lines.join("\n")}\n"
          end

          sig { params(deficit_group: DeficitGroup).returns(T::Array[String]) }
          def deficit_lines(deficit_group)
            node = deficit_group.semantic_node
            deficit_group.method_deficits.map { |method_deficit| format_method_deficit(method_deficit, node) } +
              deficit_group.lines.map { |line| format_line_deficit(line, node) } +
              deficit_group.branches.map { |branch| format_branch_deficit(branch, deficit_group.branches) }
          end

          sig { params(method_deficit: MethodDeficit, node: T.nilable(ASTResolver::SemanticNode)).returns(String) }
          def format_method_deficit(method_deficit, node)
            label = line_label(method_deficit.start_line, method_deficit.end_line)
            display_name = resolved_method_name(method_deficit, node) || method_deficit.name
            format(METHOD_DEFICIT_TMPL, label, InlineCode.span(display_name))
          end

          # A method the resolver identified (its node opens on the method's first line) is named
          # like its heading — `Owner.name` for a singleton method, which SimpleCov's merged data
          # reports under the plain owner name; a method the resolver cannot see (a dynamic
          # definition, an unparsable file) keeps the name SimpleCov derived.
          sig do
            params(method_deficit: MethodDeficit, node: T.nilable(ASTResolver::SemanticNode)).returns(T.nilable(String))
          end
          def resolved_method_name(method_deficit, node)
            return nil unless node&.method? && node.start_line == method_deficit.start_line

            node.name
          end

          sig { params(line: SimpleCov::SourceFile::Line, node: T.nilable(ASTResolver::SemanticNode)).returns(String) }
          def format_line_deficit(line, node)
            snippet = truncate_snippet(fetch_snippet_text([line.line_number], @source_lines), @config.max_snippet_lines)
            occurrence = calculate_occurrence(line.line_number, @source_lines, node)
            format(LINE_DEFICIT_TMPL, line.line_number, InlineCode.span(snippet), occurrence).rstrip
          end

          # Each branch already carries a distinct sub-snippet (via column enrichment), so a
          # line-text occurrence count is not meaningful for branches — only for line deficits.
          sig do
            params(branch: SimpleCov::SourceFile::Branch, siblings: T::Array[SimpleCov::SourceFile::Branch]).returns(String)
          end
          def format_branch_deficit(branch, siblings)
            label = line_label(branch.start_line, branch.end_line)
            snippet = InlineCode.span(branch_snippet(branch, siblings))
            format(BRANCH_DEFICIT_TMPL, label, InlineCode.span(branch.type.to_s), snippet)
          end

          # An arm whose range strictly contains other missed arms of the same node (the `else`
          # of an `elsif` chain spans the whole chain) would repeat every inner arm's text, so it
          # is cut to its first source line; every other arm quotes its exact expression.
          sig do
            params(branch: SimpleCov::SourceFile::Branch, siblings: T::Array[SimpleCov::SourceFile::Branch]).returns(String)
          end
          def branch_snippet(branch, siblings)
            if encloses_sibling?(branch, siblings)
              "#{first_source_line(branch, @source_lines)}#{TRUNCATION_ELLIPSIS}"
            else
              inline_text = extract_branch_text(branch, @source_lines, @branch_columns[branch])
              truncate_snippet(inline_text, @config.max_snippet_lines)
            end
          end

          sig do
            params(branch: SimpleCov::SourceFile::Branch, siblings: T::Array[SimpleCov::SourceFile::Branch])
              .returns(T::Boolean)
          end
          def encloses_sibling?(branch, siblings)
            arm_range = branch.start_line..branch.end_line
            siblings.any? do |sibling|
              !sibling.equal?(branch) && LineSpan.strictly_encloses?(arm_range, sibling.start_line..sibling.end_line)
            end
          end
        end
      end
    end
  end
end
