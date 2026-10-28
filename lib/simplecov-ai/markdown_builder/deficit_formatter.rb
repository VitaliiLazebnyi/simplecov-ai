# typed: strong
# frozen_string_literal: true

module SimpleCov
  module Formatter
    class AIFormatter
      class MarkdownBuilder
        # Renders the deficits of one file as Markdown fragments, one per semantic node group.
        class DeficitFormatter
          extend T::Sig

          # Error message for AST parsing failures
          ERROR_AST_FAILED = '  - **ERROR:** AST Parsing Failed. Showing raw line numbers instead.'
          # Template for node-level deficit headings
          NODE_HEADING_TEMPLATE = '- %s'
          # Coarse-grained deficit summary message
          DEFICIT_COARSE = '  - **Deficit:** Contains unexecuted lines or branches.'

          # @param markdown_lines [Array<String>] The lines of a fragment.
          # @return [String] The lines joined, each ending in a newline.
          sig { params(markdown_lines: T::Array[String]).returns(String) }
          def self.fragment(markdown_lines)
            "#{markdown_lines.join("\n")}\n"
          end

          # @param config [Configuration] The runtime toggles (granularity, snippet limits).
          # @param source_lines [Array<String>] The file's source, for snippets.
          # @param branch_columns [Hash] The branch column map from {BranchEnricher}.
          sig do
            params(config: Configuration, source_lines: T::Array[String], branch_columns: BranchEnricher::ColumnMap).void
          end
          def initialize(config, source_lines, branch_columns)
            @coarse = T.let(config.granularity == :coarse, T::Boolean)
            @snippets = T.let(SnippetFormatter.new(source_lines, config.max_snippet_lines), SnippetFormatter)
            @branch_columns = branch_columns
          end

          # @param file [SimpleCov::SourceFile] The file with deficits.
          # @param nodes [Array<ASTResolver::SemanticNode>, nil] The file's resolved nodes; nil
          #   when its AST could not be resolved.
          # @param method_deficits [Array<MethodDeficit>] The file's never-invoked methods.
          # @return [Array<String>] One fragment per semantic node group, in source order; for a
          #   file without nodes a single fragment: the parse-failure notice followed by every
          #   deficit under its raw line numbers.
          sig do
            params(file: SimpleCov::SourceFile, nodes: T.nilable(T::Array[ASTResolver::SemanticNode]),
                   method_deficits: T::Array[MethodDeficit]).returns(T::Array[String])
          end
          def render(file, nodes, method_deficits)
            return [raw_fragment(DeficitGrouper.raw_group(file, method_deficits))] unless nodes

            DeficitGrouper.build(file, nodes, method_deficits).map do |group_key, deficit_group|
              # Node-backed groups display the semantic name; the group key carries a uniqueness
              # suffix (start line) that must not appear in the report. Node-less groups fall
              # back to their positional key ("Line N" / "Lines N-M").
              node = deficit_group.semantic_node
              render_group(node ? node.name : group_key, deficit_group)
            end
          end

          private

          sig { params(deficit_group: DeficitGroup).returns(String) }
          def raw_fragment(deficit_group)
            DeficitFormatter.fragment([ERROR_AST_FAILED] + deficit_lines(deficit_group))
          end

          sig { params(display_name: String, deficit_group: DeficitGroup).returns(String) }
          def render_group(display_name, deficit_group)
            heading = format(NODE_HEADING_TEMPLATE, InlineCode.span(display_name))
            DeficitFormatter.fragment([heading] + (@coarse ? [DEFICIT_COARSE] : deficit_lines(deficit_group)))
          end

          sig { params(deficit_group: DeficitGroup).returns(T::Array[String]) }
          def deficit_lines(deficit_group)
            DeficitLines.new(deficit_group, @snippets, @branch_columns).render
          end
        end
      end
    end
  end
end
