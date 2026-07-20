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
