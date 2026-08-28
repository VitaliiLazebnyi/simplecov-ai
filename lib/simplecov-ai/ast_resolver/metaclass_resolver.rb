# typed: strict
# frozen_string_literal: true

module SimpleCov
  module Formatter
    class AIFormatter
      class ASTResolver
        # Recognizes constant assignments whose value is a `Struct.new` / `Class.new` /
        # `Module.new` / `Data.define` block. These bind an anonymous class or module to the
        # constant, so methods defined inside the block belong to that constant rather than to
        # the enclosing lexical scope.
        module MetaclassResolver
          extend T::Sig

          # Recognized builders mapped to the constructor method that signals the pattern.
          BUILDERS = T.let({ 'Struct' => :new, 'Class' => :new, 'Module' => :new, 'Data' => :define }.freeze,
                           T::Hash[String, Symbol])
          # Every AST node type that attaches a block to a call: `do … end` / `{ … }` blocks,
          # numbered-parameter blocks (`{ _1 }`) and Ruby 3.4 `it` blocks.
          BLOCK_TYPES = T.let(%i[block numblock itblock].freeze, T::Array[Symbol])

          # @param node [Parser::AST::Node] A `:casgn` constant-assignment node.
          # @return [String, nil] The builder label ("Struct"/"Class"/"Module"/"Data"), or nil
          #   if the assignment is not a recognized metaprogramming class definition.
          sig { params(node: Parser::AST::Node).returns(T.nilable(String)) }
          def self.builder_kind(node)
            send_node = builder_send(node)
            return nil unless send_node

            kind = receiver_const_name(send_node)
            BUILDERS[kind] == T.cast(send_node.children[1], Symbol) ? kind : nil
          end

          # @param node [Parser::AST::Node] Any AST node.
          # @return [Boolean] Whether the node attaches a block to a call (see {BLOCK_TYPES}).
          sig { params(node: Parser::AST::Node).returns(T::Boolean) }
          def self.block?(node)
            BLOCK_TYPES.include?(node.type)
          end

          # The method call a block node is attached to.
          #
          # @param node [Parser::AST::Node] A node whose type is one of {BLOCK_TYPES}.
          # @return [Parser::AST::Node, nil] The `:send` node the block decorates, or nil when
          #   the block belongs to something else (`super do … end`, `yield { … }`).
          sig { params(node: Parser::AST::Node).returns(T.nilable(Parser::AST::Node)) }
          def self.block_call(node)
            call = T.cast(node.children[0], Parser::AST::Node)
            call.type == :send ? call : nil
          end

          # The call a block-valued constant assignment wraps, or nil when the assignment has no
          # block value: a plain value, or the value-less `:casgn` targets that sit inside a
          # multiple assignment (`MAJOR, MINOR = …`) or an or-assignment (`FOO ||= …`).
          sig { params(node: Parser::AST::Node).returns(T.nilable(Parser::AST::Node)) }
          def self.builder_send(node)
            value = T.cast(node.children[2], T.nilable(Parser::AST::Node))
            return nil unless value && block?(value)

            block_call(value)
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
