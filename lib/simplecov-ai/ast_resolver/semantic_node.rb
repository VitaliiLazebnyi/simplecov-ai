# typed: strict
# frozen_string_literal: true

module SimpleCov
  module Formatter
    class AIFormatter
      class ASTResolver
        # An immutable value object housing the bounds and identity of one structural entity
        # (root scope, module, class or method) derived from traversing the AST.
        class SemanticNode
          extend T::Sig

          # The name Ruby itself gives the top-level execution context of a script.
          ROOT_NAME = T.let('main', String)
          # Type label of the synthetic node that spans a whole file.
          ROOT_TYPE = T.let('Root Script Scope', String)

          sig { returns(String) }
          attr_reader :name, :type

          sig { returns(Integer) }
          attr_reader :start_line, :end_line

          sig { params(name: String, type: String, start_line: Integer, end_line: Integer).void }
          def initialize(name:, type:, start_line:, end_line:)
            @name = name
            @type = type
            @start_line = start_line
            @end_line = end_line
          end

          # Builds the synthetic root node covering a whole file, so code outside any class or
          # method (and skip regions wrapping only such code) has a scope to attribute to.
          #
          # @param line_count [Integer] The number of lines in the file; an empty file still
          #   spans line 1.
          # @return [SemanticNode] The `main` node of type {ROOT_TYPE}.
          sig { params(line_count: Integer).returns(SemanticNode) }
          def self.root(line_count)
            new(name: ROOT_NAME, type: ROOT_TYPE, start_line: 1, end_line: [line_count, 1].max)
          end

          # Builds a node spanning the source lines an AST node occupies.
          #
          # @param ast_node [Parser::AST::Node] The AST node supplying the location.
          # @param name [String] The fully qualified semantic name.
          # @param type [String] The type label.
          # @return [SemanticNode] A node bounded by the AST node's first and last lines.
          sig { params(ast_node: Parser::AST::Node, name: String, type: String).returns(SemanticNode) }
          def self.spanning(ast_node, name:, type:)
            location = T.cast(ast_node.loc, Parser::Source::Map)
            new(name: name, type: type, start_line: T.cast(location.line, Integer),
                end_line: T.cast(location.last_line, Integer))
          end

          # @return [Boolean] Whether this is the synthetic root node of a file.
          sig { returns(T::Boolean) }
          def root?
            type == ROOT_TYPE
          end

          # @return [Boolean] Whether this node is a method definition (instance or singleton).
          sig { returns(T::Boolean) }
          def method?
            [NodeClassifier::TYPE_INSTANCE_METHOD, NodeClassifier::TYPE_SINGLETON_METHOD].include?(type)
          end

          # @return [Range<Integer>] The inclusive line range this node spans.
          sig { returns(T::Range[Integer]) }
          def line_range
            start_line..end_line
          end
        end
      end
    end
  end
end
