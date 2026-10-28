# typed: strong
# frozen_string_literal: true

module SimpleCov
  module Formatter
    class AIFormatter
      class ASTResolver
        # Classifies a single AST node into the semantic metadata the resolver threads through
        # traversal: the context to hand child nodes, an optional SemanticNode for the node
        # itself, and the {MethodKind} of a plain `def` among the children (singleton inside
        # `class << self`).
        module NodeClassifier
          extend T::Sig

          # The context, own node and child method kind of one classified node.
          Metadata = T.type_alias { [String, T.nilable(SemanticNode), MethodKind] }

          # @param node [Parser::AST::Node] The node to classify.
          # @param context [String] The enclosing namespace (empty at the top level).
          # @param kind [MethodKind] The kind of method a plain `def` defines in this scope.
          # @return [[String, SemanticNode, nil, MethodKind]] The child context, the node's own
          #   SemanticNode (or nil), and the method kind of the children's scope.
          sig { params(node: Parser::AST::Node, context: String, kind: MethodKind).returns(Metadata) }
          def self.classify(node, context, kind)
            case node.type
            when :class, :module then class_metadata(node, context)
            when :sclass then singleton_class_metadata(node, context)
            else definition_metadata(node, context, kind)
            end
          end

          sig { params(node: Parser::AST::Node, context: String, kind: MethodKind).returns(Metadata) }
          def self.definition_metadata(node, context, kind)
            case node.type
            when :def then method_metadata(node, context, kind)
            when :defs then singleton_method_metadata(node, context, kind)
            else assignment_metadata(node, context, kind)
            end
          end

          sig { params(node: Parser::AST::Node, context: String, kind: MethodKind).returns(Metadata) }
          def self.assignment_metadata(node, context, kind)
            if node.type == :casgn
              constant_assignment_metadata(node, context, kind)
            elsif MetaclassResolver.block?(node)
              block_metadata(node, context, kind)
            else
              [context, nil, kind]
            end
          end

          # A constant assigned a `Struct.new` / `Class.new` / `Module.new` / `Data.define` block
          # defines an anonymous class bound to that constant, so methods inside the block are
          # attributed to the constant (e.g. `Point#distance`) rather than to the enclosing
          # lexical scope.
          sig { params(node: Parser::AST::Node, context: String, kind: MethodKind).returns(Metadata) }
          def self.constant_assignment_metadata(node, context, kind)
            builder = MetaclassResolver.builder_kind(node)
            return [context, nil, kind] unless builder

            name = NodeChildren.symbol_at(node, 1).to_s
            full_name = nest(context, nest(ReceiverResolver.const_name(NodeChildren.node_at(node, 0)), name))
            [full_name, SemanticNode.spanning(node, name: full_name, type: builder), MethodKind::INSTANCE]
          end

          # A `define_method(:name) do … end` / `define_singleton_method(:name) { … }` block with
          # a literal name is the body of the method it defines, so it becomes a method node
          # spanning the block; every other block is transparent. Like a method body (see
          # {method_metadata}), the block keeps the lexical method kind for its children.
          sig { params(node: Parser::AST::Node, context: String, kind: MethodKind).returns(Metadata) }
          def self.block_metadata(node, context, kind)
            definition = DynamicMethodResolver.definition(node)
            return [context, nil, kind] unless definition

            name, singleton_definer = definition
            [context, (singleton_definer ? MethodKind::SINGLETON : kind).node_for(node, context, name), kind]
          end

          # `class << self` opens the singleton class of the lexical class, so enclosed `def`s are
          # its singleton methods. `class << obj` opens the singleton class of another object:
          # when the receiver is a simple local variable, instance variable or constant path,
          # enclosed `def`s become that receiver's singleton methods (`obj.assist`); any other
          # receiver expression keeps the lexical context.
          sig { params(node: Parser::AST::Node, context: String).returns(Metadata) }
          def self.singleton_class_metadata(node, context)
            receiver = NodeChildren.required_node_at(node, 0)
            return [context, nil, MethodKind::SINGLETON] if receiver.type == :self

            receiver_name = ReceiverResolver.singleton_class_name(receiver)
            receiver_name ? [receiver_name, nil, MethodKind::SINGLETON] : [context, nil, MethodKind::INSTANCE]
          end

          sig { params(node: Parser::AST::Node, context: String).returns(Metadata) }
          def self.class_metadata(node, context)
            new_context = nest(context, ReceiverResolver.const_name(NodeChildren.node_at(node, 0)))
            [new_context, SemanticNode.spanning(node, name: new_context, type: node.type.to_s.capitalize),
             MethodKind::INSTANCE]
          end

          # Children traverse under the enclosing context, not the method name, so a nested def
          # is attributed to its class rather than producing names like Outer#outer#inner. They
          # keep the lexical method kind: Ruby defines a def nested in a method body on the class
          # open at that point, which inside `class << self` is the singleton class.
          sig { params(node: Parser::AST::Node, context: String, kind: MethodKind).returns(Metadata) }
          def self.method_metadata(node, context, kind)
            [context, kind.node_for(node, context, NodeChildren.symbol_at(node, 0).to_s), kind]
          end

          sig { params(node: Parser::AST::Node, context: String, kind: MethodKind).returns(Metadata) }
          def self.singleton_method_metadata(node, context, kind)
            receiver_name = ReceiverResolver.singleton_method_receiver(NodeChildren.required_node_at(node, 0), context)
            [context, MethodKind::SINGLETON.node_for(node, receiver_name, NodeChildren.symbol_at(node, 1).to_s), kind]
          end

          # Qualifies a name with its enclosing context, e.g. `Outer::Inner`.
          sig { params(context: String, name: String).returns(String) }
          def self.nest(context, name)
            context.empty? ? name : "#{context}#{ReceiverResolver::NAMESPACE_SEPARATOR}#{name}"
          end

          private_class_method :definition_metadata, :assignment_metadata, :constant_assignment_metadata,
                               :block_metadata, :singleton_class_metadata, :class_metadata, :method_metadata,
                               :singleton_method_metadata, :nest
        end
      end
    end
  end
end
