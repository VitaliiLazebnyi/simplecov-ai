# typed: strong
# frozen_string_literal: true

module SimpleCov
  module Formatter
    class AIFormatter
      class ASTResolver
        # Recognizes `define_method(:name) do … end` and `define_singleton_method(:name) { … }`
        # blocks whose method name is a literal symbol or string. Such a block is the body of the
        # method it defines, so deficits inside it belong to that method rather than to the whole
        # enclosing class. Dynamic names (`define_method(name)`), explicit foreign receivers
        # (`klass.define_method`) and block-less forms (`define_method(:a, method(:b))`) are not
        # recognized and stay transparent.
        module DynamicMethodResolver
          extend T::Sig

          # Method-defining calls mapped to whether they define a singleton method.
          DEFINERS = T.let({ define_method: false, define_singleton_method: true }.freeze,
                           T::Hash[Symbol, T::Boolean])
          # Node types accepted as a literal method name.
          LITERAL_NAME_TYPES = %i[sym str].freeze

          # @param node [Parser::AST::Node] A node whose type is one of
          #   {MetaclassResolver::BLOCK_TYPES}.
          # @return [[String, Boolean], nil] The literal method name and whether the call
          #   defines a singleton method, or nil when the block is not a recognized definition.
          sig { params(node: Parser::AST::Node).returns(T.nilable([String, T::Boolean])) }
          def self.definition(node)
            call = MetaclassResolver.block_call(node)
            call && implicit_receiver?(call) ? literal_definition(call) : nil
          end

          sig { params(call: Parser::AST::Node).returns(T.nilable([String, T::Boolean])) }
          def self.literal_definition(call)
            definer = NodeChildren.symbol_at(call, 1)
            name = literal_name(call)
            [name, DEFINERS.fetch(definer)] if name && DEFINERS.key?(definer)
          end

          # True when the call has no receiver or `self` as its receiver, i.e. it defines the
          # method on the lexical class being resolved.
          sig { params(call: Parser::AST::Node).returns(T::Boolean) }
          def self.implicit_receiver?(call)
            receiver = NodeChildren.node_at(call, 0)
            !receiver || receiver.type == :self
          end

          # The first argument of the call as a method name, when it is a symbol or string literal.
          sig { params(call: Parser::AST::Node).returns(T.nilable(String)) }
          def self.literal_name(call)
            argument = NodeChildren.node_at(call, 2)
            return nil unless argument && LITERAL_NAME_TYPES.include?(argument.type)

            NodeChildren.literal_value(argument)
          end

          private_class_method :implicit_receiver?, :literal_definition, :literal_name
        end
      end
    end
  end
end
