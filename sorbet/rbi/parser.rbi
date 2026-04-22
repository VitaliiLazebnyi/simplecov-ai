# typed: strict
module Parser
  class SyntaxError < StandardError; end

  class Ruby33
    sig { params(source: String).returns([Parser::AST::Node, T::Array[T.untyped]]) }
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
