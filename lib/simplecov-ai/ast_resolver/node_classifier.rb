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
          NAMESPACE_SEPARATOR = T.let(ReceiverResolver::NAMESPACE_SEPARATOR, String)
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
            when :sclass then singleton_class_metadata(node, context)
            when :def then method_metadata(node, context, singleton)
            when :defs then singleton_method_metadata(node, context)
            when :casgn then constant_assignment_metadata(node, context, singleton)
            else MetaclassResolver.block?(node) ? block_metadata(node, context, singleton) : [context, nil, singleton]
            end
          end

          # A constant assigned a `Struct.new` / `Class.new` / `Module.new` / `Data.define` block
          # defines an anonymous class bound to that constant, so methods inside the block are
          # attributed to the constant (e.g. `Point#distance`) rather than to the enclosing
          # lexical scope.
          sig do
            params(node: Parser::AST::Node, context: String, singleton: T::Boolean)
              .returns([String, T.nilable(SemanticNode), T::Boolean])
          end
          def self.constant_assignment_metadata(node, context, singleton)
            kind = MetaclassResolver.builder_kind(node)
            return [context, nil, singleton] unless kind

            name = T.cast(node.children[1], Symbol).to_s
            scope = ReceiverResolver.const_name(T.cast(node.children[0], T.nilable(Parser::AST::Node)))
            full_name = scope.empty? ? name : "#{scope}#{NAMESPACE_SEPARATOR}#{name}"
            [nest(context, full_name), SemanticNode.spanning(node, name: nest(context, full_name), type: kind), false]
          end

          # A `define_method(:name) do … end` / `define_singleton_method(:name) { … }` block with
          # a literal name is the body of the method it defines, so it becomes a method node
          # spanning the block; every other block is transparent.
          sig do
            params(node: Parser::AST::Node, context: String, singleton: T::Boolean)
              .returns([String, T.nilable(SemanticNode), T::Boolean])
          end
          def self.block_metadata(node, context, singleton)
            definition = DynamicMethodResolver.definition(node)
            return [context, nil, singleton] unless definition

            name, singleton_definer = definition
            [context, method_node(node, context, name, singleton || singleton_definer), false]
          end

          # `class << self` opens the singleton class of the lexical class, so enclosed `def`s are
          # its singleton methods. `class << obj` opens the singleton class of another object:
          # when the receiver is a simple local variable, instance variable or constant path,
          # enclosed `def`s become that receiver's singleton methods (`obj.assist`); any other
          # receiver expression keeps the lexical context.
          sig do
            params(node: Parser::AST::Node, context: String)
              .returns([String, T.nilable(SemanticNode), T::Boolean])
          end
          def self.singleton_class_metadata(node, context)
            receiver = T.cast(node.children[0], Parser::AST::Node)
            return [context, nil, true] if receiver.type == :self

            receiver_name = ReceiverResolver.singleton_class_name(receiver)
            receiver_name ? [receiver_name, nil, true] : [context, nil, false]
          end

          sig do
            params(node: Parser::AST::Node, context: String)
              .returns([String, T.nilable(SemanticNode), T::Boolean])
          end
          def self.class_metadata(node, context)
            name = ReceiverResolver.const_name(T.cast(node.children[0], T.nilable(Parser::AST::Node)))
            new_context = nest(context, name)
            [new_context, SemanticNode.spanning(node, name: new_context, type: node.type.to_s.capitalize), false]
          end

          sig do
            params(node: Parser::AST::Node, context: String, singleton: T::Boolean)
              .returns([String, T.nilable(SemanticNode), T::Boolean])
          end
          def self.method_metadata(node, context, singleton)
            name = T.cast(node.children.first, Symbol).to_s
            # Children traverse under the enclosing context, not the method name, so a nested
            # def is attributed to its class rather than producing names like Outer#outer#inner.
            [context, method_node(node, context, name, singleton), false]
          end

          sig do
            params(node: Parser::AST::Node, context: String)
              .returns([String, T.nilable(SemanticNode), T::Boolean])
          end
          def self.singleton_method_metadata(node, context)
            receiver = T.cast(node.children[0], Parser::AST::Node)
            receiver_name = ReceiverResolver.singleton_method_receiver(receiver, context)
            name = T.cast(node.children[1], Symbol).to_s
            [context, method_node(node, receiver_name, name, true), false]
          end

          # Qualifies a name with its enclosing context, e.g. `Outer::Inner`.
          sig { params(context: String, name: String).returns(String) }
          def self.nest(context, name)
            context.empty? ? name : "#{context}#{NAMESPACE_SEPARATOR}#{name}"
          end

          # Builds a method node named `Context#name` (instance) or `Context.name` (singleton);
          # at the top level the context is empty and the name keeps just its separator.
          sig do
            params(node: Parser::AST::Node, context: String, name: String, singleton: T::Boolean)
              .returns(SemanticNode)
          end
          def self.method_node(node, context, name, singleton)
            separator = singleton ? SINGLETON_SEPARATOR : INSTANCE_SEPARATOR
            type = singleton ? TYPE_SINGLETON_METHOD : TYPE_INSTANCE_METHOD
            qualified_name = context.empty? ? "#{separator}#{name}" : "#{context}#{separator}#{name}"
            SemanticNode.spanning(node, name: qualified_name, type: type)
          end

          private_class_method :block_metadata, :singleton_class_metadata, :class_metadata, :method_metadata,
                               :singleton_method_metadata, :nest, :method_node
        end
      end
    end
  end
end
