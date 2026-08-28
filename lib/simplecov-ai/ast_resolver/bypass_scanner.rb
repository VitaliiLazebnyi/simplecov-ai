# typed: strict
# frozen_string_literal: true

module SimpleCov
  module Formatter
    class AIFormatter
      class ASTResolver
        # Attributes coverage-skip regions (line ranges SimpleCov excluded from its metrics,
        # each paired with the directive text that caused the exclusion) to the semantic nodes
        # they cover. A region is attributed to the outermost semantic nodes it fully contains,
        # or — when it sits inside a single node — to that innermost enclosing node; a region
        # wrapping only top-level code therefore lands on the root scope.
        module BypassScanner
          extend T::Sig

          # A skipped line range together with the reason SimpleCov skipped it.
          Region = T.type_alias { [T::Range[Integer], String] }
          # Reasons keyed by the node they apply to.
          ReasonsByNode = T.type_alias { T::Hash[SemanticNode, T::Array[String]] }

          # Attributes every region to the matching semantic nodes. The result is a pure
          # function of its inputs: nodes are never mutated, and a reason is listed once per
          # node even when several regions inside that node carry the same directive text.
          #
          # @param nodes [Array<SemanticNode>] The resolved structural entities in pre-order.
          # @param regions [Array<Array(Range<Integer>, String)>] Skipped ranges with reasons.
          # @return [Hash{SemanticNode => Array<String>}] The reasons attributed to each node,
          #   keyed by node identity; nodes without a bypass are absent.
          sig { params(nodes: T::Array[SemanticNode], regions: T::Array[Region]).returns(ReasonsByNode) }
          def self.attribute(nodes, regions)
            reasons_by_node = T.let({}.compare_by_identity, ReasonsByNode)
            regions.each do |range, reason|
              targets_of(nodes, range).each do |node|
                node_reasons = (reasons_by_node[node] ||= [])
                node_reasons << reason unless node_reasons.include?(reason)
              end
            end
            reasons_by_node
          end

          sig { params(nodes: T::Array[SemanticNode], range: T::Range[Integer]).returns(T::Array[SemanticNode]) }
          def self.targets_of(nodes, range)
            contained = nodes.select { |node| LineSpan.encloses?(range, node.line_range) }
            return outermost(contained) if contained.any?

            [innermost_enclosing(nodes, range)].compact
          end

          sig { params(contained: T::Array[SemanticNode]).returns(T::Array[SemanticNode]) }
          def self.outermost(contained)
            contained.reject do |node|
              contained.any? { |other| LineSpan.strictly_encloses?(other.line_range, node.line_range) }
            end
          end

          # Nodes are in pre-order, so among the (nested) nodes enclosing a region the last one
          # is the innermost — including when an inner node spans exactly the same lines as its
          # parent (a method filling its class, or a class filling the root scope).
          sig { params(nodes: T::Array[SemanticNode], range: T::Range[Integer]).returns(T.nilable(SemanticNode)) }
          def self.innermost_enclosing(nodes, range)
            nodes.reverse.find { |node| LineSpan.encloses?(node.line_range, range) }
          end

          private_class_method :targets_of, :outermost, :innermost_enclosing
        end
      end
    end
  end
end
