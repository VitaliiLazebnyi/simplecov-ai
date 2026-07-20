# typed: strict
# frozen_string_literal: true

module SimpleCov
  module Formatter
    class AIFormatter
      class ASTResolver
        # Recognizes constant assignments whose value is a `Struct.new` / `Class.new` /
        # `Data.define` block. These bind an anonymous class to the constant, so methods defined
        # inside the block belong to that constant rather than the enclosing lexical scope.
        module MetaclassResolver
          extend T::Sig

          # Recognized builders mapped to the constructor method that signals the pattern.
          BUILDERS = T.let({ 'Struct' => :new, 'Class' => :new, 'Data' => :define }.freeze,
                           T::Hash[String, Symbol])

          # @param node [Parser::AST::Node] A `:casgn` constant-assignment node.
          # @return [String, nil] The builder label ("Struct"/"Class"/"Data"), or nil if the
          #   assignment is not a recognized metaprogramming class definition.
          sig { params(node: Parser::AST::Node).returns(T.nilable(String)) }
          def self.builder_kind(node)
            send_node = builder_send(node)
            return nil unless send_node

            kind = receiver_const_name(send_node)
            BUILDERS[kind] == T.cast(send_node.children[1], Symbol) ? kind : nil
          end

          sig { params(node: Parser::AST::Node).returns(T.nilable(Parser::AST::Node)) }
          def self.builder_send(node)
            # A constant assignment always has a value, and a block always has a call, so these
            # positions are structurally present; only their node types need checking.
            value = T.cast(node.children[2], Parser::AST::Node)
            return nil unless value.type == :block

            send_node = T.cast(value.children[0], Parser::AST::Node)
            send_node if send_node.type == :send
          end

          sig { params(send_node: Parser::AST::Node).returns(String) }
          def self.receiver_const_name(send_node)
            receiver = T.cast(send_node.children[0], T.nilable(Parser::AST::Node))
            return '' unless receiver && receiver.type == :const

            T.cast(receiver.children[1], Symbol).to_s
          end

          private_class_method :builder_send, :receiver_const_name
        end
      end
    end
  end
end
