# typed: strict
# frozen_string_literal: true

module SimpleCov
  module Formatter
    class AIFormatter
      class ASTResolver
        # Resolves the receiver expressions that name scopes: constant paths (`Foo::Bar`), the
        # object a `class << receiver` singleton class opens on, and the target of a
        # `def receiver.method` singleton definition.
        module ReceiverResolver
          extend T::Sig

          # Separator used to denote namespace nesting (e.g., Module::Class)
          NAMESPACE_SEPARATOR = T.let('::', String)

          # Reconstructs a fully-qualified constant path (e.g. `Foo::Bar`) from a const node so
          # compact class definitions do not lose their namespace prefix.
          #
          # @param node [Parser::AST::Node, nil] A `:const` node, or any other node.
          # @return [String] The constant path, or an empty string for a non-constant node.
          sig { params(node: T.nilable(Parser::AST::Node)).returns(String) }
          def self.const_name(node)
            return '' unless node && node.type == :const

            scope = const_name(NodeChildren.node_at(node, 0))
            name = NodeChildren.symbol_at(node, 1).to_s
            scope.empty? ? name : "#{scope}#{NAMESPACE_SEPARATOR}#{name}"
          end

          # Names the object a `class << receiver` singleton class opens on when the receiver is
          # a simple local variable, instance variable or constant path — the forms whose source
          # text identifies the object (`obj`, `@registry`, `Foo::Bar`).
          #
          # @param receiver [Parser::AST::Node] The receiver node of an `:sclass` node.
          # @return [String, nil] The receiver's source name, or nil for any other expression.
          sig { params(receiver: Parser::AST::Node).returns(T.nilable(String)) }
          def self.singleton_class_name(receiver)
            case receiver.type
            when :lvar, :ivar then NodeChildren.variable_name(receiver).to_s
            when :const then const_name(receiver)
            end
          end

          # Determines the receiver a `def receiver.method` singleton definition targets: the
          # explicit constant path for a foreign receiver such as `def String.shout`, otherwise
          # the enclosing context — for `self` and for any non-constant expression (`def obj.foo`).
          #
          # @param receiver [Parser::AST::Node] The receiver node of a `:defs` node.
          # @param context [String] The enclosing lexical context.
          # @return [String] The name the singleton method is attributed to.
          sig { params(receiver: Parser::AST::Node, context: String).returns(String) }
          def self.singleton_method_receiver(receiver, context)
            const = const_name(receiver)
            const.empty? ? context : const
          end
        end
      end
    end
  end
end
