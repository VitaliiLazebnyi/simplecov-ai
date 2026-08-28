# typed: strict
# frozen_string_literal: true

module SimpleCov
  module Formatter
    class AIFormatter
      class ASTResolver
        # A mutable value object housing bounds, identification metrics, and coverage-bypass
        # reasons derived from traversing the AST nodes. Bounds and identity are fixed at
        # construction; bypass reasons accumulate via {#add_bypass} during resolution.
        class SemanticNode
          extend T::Sig

          # The name Ruby itself gives the top-level execution context of a script.
          ROOT_NAME = T.let('main', String)
          # Type label of the synthetic node that spans a whole file.
          ROOT_TYPE = T.let('Root Script Scope', String)

          sig { returns(String) }
          attr_reader :name, :type

          sig { returns(Integer) }
          attr_reader :start_line, :end_line

          sig { returns(T::Array[String]) }
          attr_reader :bypass_reasons

          sig do
            params(
              name: String,
              type: String,
              start_line: Integer,
              end_line: Integer,
              bypass_reasons: T::Array[String]
            ).void
          end
          def initialize(name:, type:, start_line:, end_line:, bypass_reasons: [])
            @name = name
            @type = type
            @start_line = start_line
            @end_line = end_line
            @bypass_reasons = bypass_reasons
          end

          # Builds the synthetic root node covering a whole file, so code outside any class or
          # method (and bypass regions wrapping only such code) has a scope to attribute to.
          #
          # @param line_count [Integer] The number of lines in the file; an empty file still
          #   spans line 1.
          # @return [SemanticNode] The `main` node of type {ROOT_TYPE}.
          sig { params(line_count: Integer).returns(SemanticNode) }
          def self.root(line_count)
            new(name: ROOT_NAME, type: ROOT_TYPE, start_line: 1, end_line: [line_count, 1].max)
          end

          # Builds a node spanning the source lines an AST node occupies.
          #
          # @param ast_node [Parser::AST::Node] The AST node supplying the location.
          # @param name [String] The fully qualified semantic name.
          # @param type [String] The type label.
          # @return [SemanticNode] A node bounded by the AST node's first and last lines.
          sig { params(ast_node: Parser::AST::Node, name: String, type: String).returns(SemanticNode) }
          def self.spanning(ast_node, name:, type:)
            location = T.cast(ast_node.loc, Parser::Source::Map)
            new(name: name, type: type, start_line: T.cast(location.line, Integer),
                end_line: T.cast(location.last_line, Integer))
          end

          # @return [Boolean] Whether this is the synthetic root node of a file.
          sig { returns(T::Boolean) }
          def root?
            type == ROOT_TYPE
          end

          # Records a coverage-bypass directive that applies to this node.
          #
          # @param bypass_reason [String] The directive text, e.g. `# :nocov:`.
          # @return [void]
          sig { params(bypass_reason: String).void }
          def add_bypass(bypass_reason)
            @bypass_reasons << bypass_reason
          end
        end
      end
    end
  end
end
