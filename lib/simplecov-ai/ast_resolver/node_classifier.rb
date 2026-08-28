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
          # Owner of a method defined at the top level of a file with a plain `def`: Ruby adds it
          # to Object (as a private method), and SimpleCov's method coverage names it that way too
          TOP_LEVEL_INSTANCE_OWNER = T.let('Object', String)

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
            when :defs then singleton_method_metadata(node, context, singleton)
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

            name = NodeChildren.symbol_at(node, 1).to_s
            full_name = nest(context, nest(ReceiverResolver.const_name(NodeChildren.node_at(node, 0)), name))
            [full_name, SemanticNode.spanning(node, name: full_name, type: kind), false]
          end

          # A `define_method(:name) do … end` / `define_singleton_method(:name) { … }` block with
          # a literal name is the body of the method it defines, so it becomes a method node
          # spanning the block; every other block is transparent. Like a method body (see
          # {method_metadata}), the block keeps the lexical singleton scope for its children.
          sig do
            params(node: Parser::AST::Node, context: String, singleton: T::Boolean)
              .returns([String, T.nilable(SemanticNode), T::Boolean])
          end
          def self.block_metadata(node, context, singleton)
            definition = DynamicMethodResolver.definition(node)
            return [context, nil, singleton] unless definition

            name, singleton_definer = definition
            [context, method_node(node, context, name, singleton || singleton_definer), singleton]
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
            receiver = NodeChildren.required_node_at(node, 0)
            return [context, nil, true] if receiver.type == :self

            receiver_name = ReceiverResolver.singleton_class_name(receiver)
            receiver_name ? [receiver_name, nil, true] : [context, nil, false]
          end

          sig do
            params(node: Parser::AST::Node, context: String)
              .returns([String, T.nilable(SemanticNode), T::Boolean])
          end
          def self.class_metadata(node, context)
            new_context = nest(context, ReceiverResolver.const_name(NodeChildren.node_at(node, 0)))
            [new_context, SemanticNode.spanning(node, name: new_context, type: node.type.to_s.capitalize), false]
          end

          # Children traverse under the enclosing context, not the method name, so a nested def
          # is attributed to its class rather than producing names like Outer#outer#inner. They
          # keep the lexical singleton scope: Ruby defines a def nested in a method body on the
          # class open at that point, which inside `class << self` is the singleton class.
          sig do
            params(node: Parser::AST::Node, context: String, singleton: T::Boolean)
              .returns([String, T.nilable(SemanticNode), T::Boolean])
          end
          def self.method_metadata(node, context, singleton)
            [context, method_node(node, context, NodeChildren.symbol_at(node, 0).to_s, singleton), singleton]
          end

          sig do
            params(node: Parser::AST::Node, context: String, singleton: T::Boolean)
              .returns([String, T.nilable(SemanticNode), T::Boolean])
          end
          def self.singleton_method_metadata(node, context, singleton)
            receiver = NodeChildren.required_node_at(node, 0)
            receiver_name = ReceiverResolver.singleton_method_receiver(receiver, context)
            [context, method_node(node, receiver_name, NodeChildren.symbol_at(node, 1).to_s, true), singleton]
          end

          # Qualifies a name with its enclosing context, e.g. `Outer::Inner`.
          sig { params(context: String, name: String).returns(String) }
          def self.nest(context, name)
            context.empty? ? name : "#{context}#{NAMESPACE_SEPARATOR}#{name}"
          end

          # Builds a method node named `Context#name` (instance) or `Context.name` (singleton). At
          # the top level the context is empty and the owner is the one Ruby uses there: `Object`
          # for a plain `def` (`Object#name`, the name SimpleCov's method coverage reports as well)
          # and `main`, the top-level object, for a singleton definition (`main.name`).
          sig do
            params(node: Parser::AST::Node, context: String, name: String, singleton: T::Boolean)
              .returns(SemanticNode)
          end
          def self.method_node(node, context, name, singleton)
            owner = context.empty? ? top_level_owner(singleton) : context
            separator = singleton ? SINGLETON_SEPARATOR : INSTANCE_SEPARATOR
            type = singleton ? TYPE_SINGLETON_METHOD : TYPE_INSTANCE_METHOD
            SemanticNode.spanning(node, name: "#{owner}#{separator}#{name}", type: type, method_name: name)
          end

          sig { params(singleton: T::Boolean).returns(String) }
          def self.top_level_owner(singleton)
            singleton ? SemanticNode::ROOT_NAME : TOP_LEVEL_INSTANCE_OWNER
          end

          private_class_method :block_metadata, :singleton_class_metadata, :class_metadata, :method_metadata,
                               :singleton_method_metadata, :nest, :method_node, :top_level_owner
        end
      end
    end
  end
end
