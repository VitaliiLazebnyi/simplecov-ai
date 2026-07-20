# typed: strict
# frozen_string_literal: true

module SimpleCov
  module Formatter
    class AIFormatter
      class ASTResolver
        # Classifies a single AST node into the semantic metadata the resolver threads through
        # traversal: the context to hand child nodes, an optional SemanticNode for the node
        # itself, and whether children sit inside a singleton class (`class << self`).
        module NodeClassifier
          extend T::Sig

          # Separator used to denote namespace nesting (e.g., Module::Class)
          NAMESPACE_SEPARATOR = T.let('::', String)
          # Separator used to denote instance methods (e.g., Class#method)
          INSTANCE_SEPARATOR = T.let('#', String)
          # Separator used to denote singleton/class methods (e.g., Class.method)
          SINGLETON_SEPARATOR = T.let('.', String)
          # Label applied to nodes representing instance methods
          TYPE_INSTANCE_METHOD = T.let('Instance Method', String)
          # Label applied to nodes representing singleton methods
          TYPE_SINGLETON_METHOD = T.let('Singleton Method', String)

          # @return [[String, SemanticNode, nil, Boolean]] The child context, the node's own
          #   SemanticNode (or nil), and whether children are in singleton scope.
          sig do
            params(node: Parser::AST::Node, context: String, singleton: T::Boolean)
              .returns([String, T.nilable(SemanticNode), T::Boolean])
          end
          def self.classify(node, context, singleton)
            case node.type
            when :class, :module then class_metadata(node, context)
            when :sclass then [context, nil, singleton_receiver?(node)]
            when :def then method_metadata(node, context, singleton)
            when :defs then singleton_method_metadata(node, context)
            when :casgn then constant_assignment_metadata(node, context, singleton)
            else [context, nil, singleton]
            end
          end

          # A constant assigned a `Struct.new` / `Class.new` / `Data.define` block defines an
          # anonymous class bound to that constant, so methods inside the block are attributed to
          # the constant (e.g. `Point#distance`) rather than to the enclosing lexical scope.
          sig do
            params(node: Parser::AST::Node, context: String, singleton: T::Boolean)
              .returns([String, T.nilable(SemanticNode), T::Boolean])
          end
          def self.constant_assignment_metadata(node, context, singleton)
            kind = MetaclassResolver.builder_kind(node)
            return [context, nil, singleton] unless kind

            name = T.cast(node.children[1], Symbol).to_s
            scope = const_name(T.cast(node.children[0], T.nilable(Parser::AST::Node)))
            full_name = scope.empty? ? name : "#{scope}#{NAMESPACE_SEPARATOR}#{name}"
            new_context = context.empty? ? full_name : "#{context}#{NAMESPACE_SEPARATOR}#{full_name}"
            [new_context, build_node(node, new_context, kind), false]
          end

          # True when a singleton class opens on `self` (`class << self`), the only receiver for
          # which enclosed `def`s are unambiguously singleton methods of the lexical class.
          sig { params(node: Parser::AST::Node).returns(T::Boolean) }
          def self.singleton_receiver?(node)
            T.cast(node.children[0], Parser::AST::Node).type == :self
          end

          sig do
            params(node: Parser::AST::Node, context: String)
              .returns([String, T.nilable(SemanticNode), T::Boolean])
          end
          def self.class_metadata(node, context)
            name = const_name(T.cast(node.children[0], T.nilable(Parser::AST::Node)))
            new_context = context.empty? ? name : "#{context}#{NAMESPACE_SEPARATOR}#{name}"
            [new_context, build_node(node, new_context, node.type.to_s.capitalize), false]
          end

          # Reconstructs a fully-qualified constant path (e.g. `Foo::Bar`) from a const node so
          # compact class definitions do not lose their namespace prefix.
          sig { params(node: T.nilable(Parser::AST::Node)).returns(String) }
          def self.const_name(node)
            return '' unless node.is_a?(Parser::AST::Node) && node.type == :const

            scope = const_name(T.cast(node.children[0], T.nilable(Parser::AST::Node)))
            name = T.cast(node.children[1], Symbol).to_s
            scope.empty? ? name : "#{scope}#{NAMESPACE_SEPARATOR}#{name}"
          end

          sig do
            params(node: Parser::AST::Node, context: String, singleton: T::Boolean)
              .returns([String, T.nilable(SemanticNode), T::Boolean])
          end
          def self.method_metadata(node, context, singleton)
            name = T.cast(node.children.first, Symbol).to_s
            separator = singleton ? SINGLETON_SEPARATOR : INSTANCE_SEPARATOR
            type = singleton ? TYPE_SINGLETON_METHOD : TYPE_INSTANCE_METHOD
            new_context = context.empty? ? "#{separator}#{name}" : "#{context}#{separator}#{name}"
            # Children traverse under the enclosing context, not the method name, so a nested
            # def is attributed to its class rather than producing names like Outer#outer#inner.
            [context, build_node(node, new_context, type), false]
          end

          sig do
            params(node: Parser::AST::Node, context: String)
              .returns([String, T.nilable(SemanticNode), T::Boolean])
          end
          def self.singleton_method_metadata(node, context)
            receiver_name = defs_receiver_name(T.cast(node.children[0], Parser::AST::Node), context)
            name = T.cast(node.children[1], Symbol).to_s
            new_context = "#{receiver_name}#{SINGLETON_SEPARATOR}#{name}"
            [context, build_node(node, new_context, TYPE_SINGLETON_METHOD), false]
          end

          # Determines the receiver a `def receiver.method` singleton definition targets: the
          # lexical class for `self`, the explicit constant path for a foreign receiver such as
          # `def String.shout`, or the enclosing context when the receiver is a non-constant
          # expression (e.g. `def obj.foo`).
          sig { params(receiver: Parser::AST::Node, context: String).returns(String) }
          def self.defs_receiver_name(receiver, context)
            return context if receiver.type == :self

            const = const_name(receiver)
            const.empty? ? context : const
          end

          sig { params(node: Parser::AST::Node, name: String, type: String).returns(SemanticNode) }
          def self.build_node(node, name, type)
            loc = T.cast(node.loc, Parser::Source::Map)
            start_line = T.cast(loc.line, Integer)
            end_line = T.cast(loc.last_line, Integer)
            SemanticNode.new(name: name, type: type, start_line: start_line, end_line: end_line, bypass_reasons: [])
          end

          private_class_method :singleton_receiver?, :class_metadata, :const_name, :method_metadata,
                               :singleton_method_metadata, :defs_receiver_name, :build_node
        end
      end
    end
  end
end
