# typed: strong
# frozen_string_literal: true

module SimpleCov
  module Formatter
    class AIFormatter
      class ASTResolver
        # Typed access to the children of Parser AST nodes. Parser types every child as an
        # arbitrary object while each node type the resolver reads has one known shape (`:def`
        # holds its name Symbol first, `:casgn` its scope node, name Symbol and value node), so
        # the runtime type checks live here and every call site names the child it reads and
        # nothing else. A child of an unexpected type raises TypeError, never a wrong result.
        module NodeChildren
          extend T::Sig

          # @param node [Parser::AST::Node] The parent node.
          # @return [Array<Parser::AST::Node>] The children that are nodes themselves, in order
          #   (names, literal values and absent children are left out).
          sig { params(node: Parser::AST::Node).returns(T::Array[Parser::AST::Node]) }
          def self.nodes(node)
            node.children.each_index.filter_map { |index| node_at(node, index) }
          end

          # @param node [Parser::AST::Node] The parent node.
          # @param index [Integer] The position of the child.
          # @return [Parser::AST::Node, nil] The child node, or nil when the child is absent or
          #   not a node.
          sig { params(node: Parser::AST::Node, index: Integer).returns(T.nilable(Parser::AST::Node)) }
          def self.node_at(node, index)
            child = node.children.at(index)
            case child
            when Parser::AST::Node then child
            end
          end

          # @param node [Parser::AST::Node] The parent node.
          # @param index [Integer] The position of a child the grammar guarantees to be present.
          # @return [Parser::AST::Node] The child node.
          # @raise [TypeError] When the child is not a node.
          sig { params(node: Parser::AST::Node, index: Integer).returns(Parser::AST::Node) }
          def self.required_node_at(node, index)
            node_at(node, index) || raise(TypeError, unexpected(node, index, 'a node'))
          end

          # @param node [Parser::AST::Node] The parent node.
          # @param index [Integer] The position of a child the grammar guarantees to be a Symbol.
          # @return [Symbol] The child.
          # @raise [TypeError] When the child is not a Symbol.
          sig { params(node: Parser::AST::Node, index: Integer).returns(Symbol) }
          def self.symbol_at(node, index)
            child = node.children.at(index)
            case child
            when Symbol then child
            else raise TypeError, unexpected(node, index, 'a Symbol')
            end
          end

          # @param node [Parser::AST::Node] A `:sym` or `:str` literal node.
          # @return [String] The literal's value as a String.
          # @raise [TypeError] When the value is neither a Symbol nor a String.
          sig { params(node: Parser::AST::Node).returns(String) }
          def self.literal_value(node)
            child = node.children.at(0)
            case child
            when Symbol, String then child.to_s
            else raise TypeError, unexpected(node, 0, 'a Symbol or String')
            end
          end

          sig { params(node: Parser::AST::Node, index: Integer, expected: String).returns(String) }
          def self.unexpected(node, index, expected)
            "child #{index} of a :#{node.type} node is not #{expected}"
          end

          private_class_method :unexpected
        end
      end
    end
  end
end
