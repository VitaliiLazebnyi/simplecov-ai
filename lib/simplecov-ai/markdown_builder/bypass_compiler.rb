# typed: strong
# frozen_string_literal: true

module SimpleCov
  module Formatter
    class AIFormatter
      class MarkdownBuilder
        # Reports, per file, the coverage bypasses SimpleCov honoured in this run, resolved to
        # the semantic nodes they cover.
        class BypassCompiler
          extend T::Sig

          # Section heading for bypassed coverage
          HEADING = "## Ignored Coverage Bypasses\n\n"
          # Template for a bypassed node heading
          NODE_HEADING_TEMPLATE = '- %s'
          # Template detailing the specific directive that ignored coverage for a node
          REASON_TEMPLATE = '  - **Bypass Present:** Coverage explicitly ignored via %s.'

          sig { params(coverage_metrics: SimpleCov::Result, builder: MarkdownBuilder).void }
          def initialize(coverage_metrics, builder)
            @coverage_metrics = coverage_metrics
            @builder = builder
          end

          # Writes the bypass section through the budget, one file block at a time.
          #
          # @param budget [ReportBudget] The budget every fragment is admitted through.
          # @return [Integer] The number of files with bypasses that were omitted or cut short.
          sig { params(budget: ReportBudget).returns(Integer) }
          def write_bypasses(budget)
            blocks = @coverage_metrics.files.to_a.filter_map { |file| file_block(file) }
            SectionWriter.new(budget, HEADING).write_blocks(blocks)
          end

          private

          # The expensive AST resolution only runs for files SimpleCov actually skipped
          # something in; a file whose AST cannot be resolved reports no bypasses, and a file
          # whose coverage data SimpleCov cannot decode reports the decode guard's error entry.
          # The heading and node fragments of a file with bypasses; nil for a file without any.
          sig { params(file: SimpleCov::SourceFile).returns(T.nilable([String, T::Array[String]])) }
          def file_block(file)
            node_fragments = render_file(file)
            [SectionWriter.file_heading(file), node_fragments] unless node_fragments.empty?
          end

          sig { params(file: SimpleCov::SourceFile).returns(T::Array[String]) }
          def render_file(file)
            DecodeGuard.render { SkipRegions.any?(file) ? render_skip_regions(file) : [] }
          end

          sig { params(file: SimpleCov::SourceFile).returns(T::Array[String]) }
          def render_skip_regions(file)
            nodes = @builder.try_resolve_ast(file.filename)
            return [] unless nodes

            render_nodes(nodes, ASTResolver::BypassScanner.attribute(nodes, SkipRegions.of(file, SourceLines.of(file))))
          end

          sig do
            params(nodes: T::Array[ASTResolver::SemanticNode], reasons_by_node: ASTResolver::BypassScanner::ReasonsByNode)
              .returns(T::Array[String])
          end
          def render_nodes(nodes, reasons_by_node)
            nodes.filter_map do |node|
              reasons = reasons_by_node[node]
              render_node(node, reasons) if reasons
            end
          end

          sig { params(node: ASTResolver::SemanticNode, reasons: T::Array[String]).returns(String) }
          def render_node(node, reasons)
            heading = format(NODE_HEADING_TEMPLATE, InlineCode.span(node.name))
            reason_lines = reasons.map { |reason| format(REASON_TEMPLATE, InlineCode.span(reason)) }
            "#{([heading] + reason_lines).join("\n")}\n"
          end
        end
      end
    end
  end
end
