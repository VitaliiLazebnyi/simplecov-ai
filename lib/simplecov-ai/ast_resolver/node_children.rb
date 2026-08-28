# typed: strict
# frozen_string_literal: true

module SimpleCov
  module Formatter
    class AIFormatter
      class ASTResolver
        # Typed access to the children of Parser AST nodes. Parser types every child as untyped
        # while each node type the resolver reads has one known shape (`:def` holds its name
        # Symbol first, `:casgn` its scope node, name Symbol and value node), so the casts live
        # here and every call site names the child it reads and nothing else.
        module NodeChildren
          extend T::Sig

          # @param node [Parser::AST::Node] The parent node.
          # @param index [Integer] The position of the child.
          # @return [Parser::AST::Node, nil] The child node, or nil when the child is absent.
          sig { params(node: Parser::AST::Node, index: Integer).returns(T.nilable(Parser::AST::Node)) }
          def self.node_at(node, index)
            T.cast(node.children[index], T.nilable(Parser::AST::Node))
          end

          # @param node [Parser::AST::Node] The parent node.
          # @param index [Integer] The position of a child the grammar guarantees to be present.
          # @return [Parser::AST::Node] The child node.
          sig { params(node: Parser::AST::Node, index: Integer).returns(Parser::AST::Node) }
          def self.required_node_at(node, index)
            T.cast(node.children[index], Parser::AST::Node)
          end

          # @param node [Parser::AST::Node] The parent node.
          # @param index [Integer] The position of a child the grammar guarantees to be a Symbol.
          # @return [Symbol] The child.
          sig { params(node: Parser::AST::Node, index: Integer).returns(Symbol) }
          def self.symbol_at(node, index)
            T.cast(node.children[index], Symbol)
          end

          # @param node [Parser::AST::Node] A `:lvar` or `:ivar` node, whose only child is its name.
          # @return [Symbol] The variable's name.
          sig { params(node: Parser::AST::Node).returns(Symbol) }
          def self.variable_name(node)
            T.cast(node.children[0], Symbol)
          end

          # @param node [Parser::AST::Node] A `:sym` or `:str` literal node.
          # @return [String] The literal's value as a String.
          sig { params(node: Parser::AST::Node).returns(String) }
          def self.literal_value(node)
            T.cast(node.children[0], T.any(Symbol, String)).to_s
          end
        end
      end
    end
  end
end
