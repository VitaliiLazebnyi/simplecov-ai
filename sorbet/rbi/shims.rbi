# typed: strict

# Declarations for the type checker only; nothing here exists at runtime.
module SimpleCov
  module Formatter
    class AIFormatter
      class ASTResolver
        # Only ever extended onto a `parser` builder (see ParserBackend.parse), whose private
        # token readers it calls.
        module LenientLiterals
          extend T::Helpers

          requires_ancestor { Parser::Builders::Default }
        end
      end
    end
  end
end

# Ruby >= 3.2 (and TruffleRuby); the suite asks for it only where `Coverage` responds to it.
module Coverage
  sig { params(mode: Symbol).returns(T::Boolean) }
  def self.supported?(mode); end
end
