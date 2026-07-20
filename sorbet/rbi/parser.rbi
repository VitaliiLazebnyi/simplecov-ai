# typed: strict
module Parser
  class SyntaxError < StandardError; end

  # Parser::CurrentRuby is a machine-generated alias for the concrete grammar class
  # (Parser::Ruby33 under the bundled parser gem). parse_with_comments returns a nil AST
  # for empty or comment-only sources, so the node is nilable.
  class Ruby33
    sig { params(source: String).returns([T.nilable(Parser::AST::Node), T::Array[T.untyped]]) }
    def self.parse_with_comments(source); end
  end

  module AST
    class Node
      sig { returns(Symbol) }
      def type; end

      sig { returns(T::Array[T.untyped]) }
      def children; end

      sig { returns(T.untyped) }
      def loc; end
    end
  end
end
