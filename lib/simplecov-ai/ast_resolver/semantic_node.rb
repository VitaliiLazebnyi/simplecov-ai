# typed: strong
# frozen_string_literal: true

module SimpleCov
  module Formatter
    class AIFormatter
      class ASTResolver
        # An immutable value object housing the bounds and identity of one structural entity
        # (root scope, module, class or method) derived from traversing the AST. Nodes are
        # compared by identity.
        class SemanticNode < T::Struct
          extend T::Sig

          # The name Ruby itself gives the top-level execution context of a script.
          ROOT_NAME = 'main'
          # Type label of the synthetic node that spans a whole file.
          ROOT_TYPE = 'Root Script Scope'

          # @return [String] The fully qualified semantic name (`Sample::Calc#sign`).
          const :name, String
          # @return [String] The type label (`Class`, `Instance Method`, ...).
          const :type, String
          # @return [Integer] The first source line the node spans.
          const :start_line, Integer
          # @return [Integer] The last source line the node spans.
          const :end_line, Integer
          # @return [String, nil] The bare method name of a method node (`sign` of
          #   `Sample::Calc#sign`); nil for every other kind of node. (Left out rather than given a
          #   `default:`, whose sorbet-runtime machinery fails on JRuby.)
          const :method_name, T.nilable(String)

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
            location = ast_node.loc
            new(name: name, type: type, start_line: location.line, end_line: location.last_line)
          end

          # Whether this is the node of the method SimpleCov reported starting on `line` under
          # the bare name `name`.
          #
          # @param line [Integer] The method's first line.
          # @param name [String] The method's bare name.
          # @return [Boolean] Whether the node opens on that line and carries that method name.
          sig { params(line: Integer, name: String).returns(T::Boolean) }
          def defines?(line, name)
            [start_line, method_name] == [line, name]
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
