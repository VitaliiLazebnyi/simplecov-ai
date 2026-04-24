# typed: strict
# frozen_string_literal: true

module SimpleCov
  module Formatter
    class AIFormatter
      class ASTResolver
        # An immutable struct housing bounds, identification metrics, and static bypassing
        # definitions derived from traversing the AST nodes.
        class SemanticNode
          extend T::Sig

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

          sig { params(bypass_reason: String).void }
          def add_bypass(bypass_reason)
            @bypass_reasons << bypass_reason
          end
        end
      end
    end
  end
end
