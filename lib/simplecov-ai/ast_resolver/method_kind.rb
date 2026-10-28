# typed: strong
# frozen_string_literal: true

module SimpleCov
  module Formatter
    class AIFormatter
      class ASTResolver
        # How a `def` is named and labelled in the lexical scope it appears in: an instance
        # method is `Owner#name`, a singleton method (`def self.x`, any `def` inside
        # `class << self`) `Owner.name`. The two kinds are the constants {INSTANCE} and
        # {SINGLETON}; traversal threads the kind of the current scope down to its children.
        class MethodKind < T::Struct
          extend T::Sig

          # @return [String] Joins the owner and the method name.
          const :separator, String
          # @return [String] The type label of the method nodes.
          const :type, String
          # @return [String] The owner Ruby gives a method of this kind defined at the top level
          #   of a file.
          const :top_level_owner, String

          # Methods defined with a plain `def` outside a singleton class.
          INSTANCE = T.let(new(separator: '#', type: 'Instance Method', top_level_owner: 'Object'), MethodKind)
          # Methods defined on an explicit receiver or inside a singleton class.
          SINGLETON = T.let(
            new(separator: '.', type: 'Singleton Method', top_level_owner: SemanticNode::ROOT_NAME), MethodKind
          )

          # Builds the node of a method of this kind. At the top level the context is empty and
          # the owner is the one Ruby uses there: `Object` for a plain `def` (`Object#name`, the
          # name SimpleCov's method coverage reports as well) and `main`, the top-level object,
          # for a singleton definition (`main.name`).
          #
          # @param ast_node [Parser::AST::Node] The definition, supplying the location.
          # @param context [String] The owner's name; empty at the top level.
          # @param name [String] The bare method name.
          # @return [SemanticNode] The method node.
          sig { params(ast_node: Parser::AST::Node, context: String, name: String).returns(SemanticNode) }
          def node_for(ast_node, context, name)
            owner = context.empty? ? top_level_owner : context
            location = ast_node.loc
            SemanticNode.new(name: "#{owner}#{separator}#{name}", type: type, start_line: location.line,
                             end_line: location.last_line, method_name: name)
          end
        end
      end
    end
  end
end
