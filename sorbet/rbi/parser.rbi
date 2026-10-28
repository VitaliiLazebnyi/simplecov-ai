# typed: strict

# Typed overlay for the `parser` and `ast` gems. The generated RBIs under sorbet/rbi/gems
# (`rake typecheck` generates them) reflect every method but carry no signatures, and
# `srb tc --typed strong` rejects untyped values, so the methods the library calls are given the
# signatures their documentation states here. Each definition must keep the exact arity of its
# generated counterpart, otherwise Sorbet reports a conflicting redefinition.
module Parser
  class Base
    # Parser::CurrentRuby is an alias for the grammar class matching the running Ruby (see the
    # generated parser RBI), so this signature covers `Parser::CurrentRuby.parse_with_comments`.
    # The AST is nil for empty or comment-only sources.
    sig do
      params(string: String, file: String, line: Integer)
        .returns([T.nilable(Parser::AST::Node), T::Array[Parser::Source::Comment]])
    end
    def self.parse_with_comments(string, file = '(string)', line = 1); end

    sig { params(builder: Parser::Builders::Default).void }
    def initialize(builder = Parser::Builders::Default.new); end

    sig { returns(Parser::Builders::Default) }
    def builder; end

    sig { returns(Parser::Diagnostic::Engine) }
    def diagnostics; end

    # The AST is nil for empty or comment-only sources.
    sig { params(source_buffer: Parser::Source::Buffer).returns(T.nilable(Parser::AST::Node)) }
    def parse(source_buffer); end
  end

  module AST
    class Node
      sig { returns(Parser::Source::Map) }
      def loc; end
    end
  end

  class Diagnostic
    class Engine
      sig { params(_arg0: T::Boolean).returns(T::Boolean) }
      def all_errors_are_fatal=(_arg0); end
    end
  end

  module Source
    class Map
      sig { returns(Integer) }
      def line; end

      sig { returns(Integer) }
      def last_line; end
    end
  end
end

module AST
  class Node
    sig { returns(Symbol) }
    def type; end

    sig { returns(T::Array[BasicObject]) }
    def children; end
  end
end
