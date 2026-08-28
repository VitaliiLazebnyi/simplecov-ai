# typed: strict

# Typed overlay for the `parser` and `ast` gems. The generated RBIs under sorbet/rbi/gems reflect
# every method but carry no signatures, and `srb tc --typed strong` rejects untyped intermediate
# values, so the methods the library calls without an immediate `T.cast` are given signatures
# here. Each definition must keep the exact arity of its generated counterpart, otherwise Sorbet
# reports a conflicting redefinition. Methods whose results the library already narrows with
# `T.cast` (e.g. `Parser::AST::Node#loc`, `Parser::Source::Map#line`) are deliberately left
# untyped so those casts stay meaningful.
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
  end
end

module AST
  class Node
    sig { returns(Symbol) }
    def type; end

    sig { returns(T::Array[T.untyped]) }
    def children; end
  end
end
