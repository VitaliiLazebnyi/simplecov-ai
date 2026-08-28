# typed: strict
# frozen_string_literal: true

module SimpleCov
  module Formatter
    class AIFormatter
      class ASTResolver
        # Extended onto a `parser` builder so it accepts string literals whose escape sequences
        # produce bytes that are invalid in the source encoding (e.g. `"\xf0-\xff"`). MRI and
        # Prism accept such literals, but the `parser` builder rejects them with "literal
        # contains escape sequences incompatible with UTF-8", which would discard the structure
        # of an otherwise valid file.
        module LenientLiterals
          extend T::Sig

          # @param token [Array] The `[value, location]` pair the lexer emits for a literal.
          # @return [String] The literal value, skipping the encoding validity check.
          sig { params(token: T::Array[BasicObject]).returns(BasicObject) }
          def string_value(token)
            token.fetch(0)
          end
        end
      end
    end
  end
end
