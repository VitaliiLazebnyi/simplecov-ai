# typed: strict
# frozen_string_literal: true

module SimpleCov
  module Formatter
    class AIFormatter
      # Containment predicates over inclusive source-line ranges, shared by bypass attribution
      # (skip regions against semantic nodes) and branch rendering (arms against sibling arms).
      module LineSpan
        extend T::Sig

        # @param outer [Range<Integer>] The candidate enclosing range.
        # @param inner [Range<Integer>] The range that may be enclosed.
        # @return [Boolean] Whether every line of `inner` lies within `outer`.
        sig { params(outer: T::Range[Integer], inner: T::Range[Integer]).returns(T::Boolean) }
        def self.encloses?(outer, inner)
          outer.begin <= inner.begin && outer.end >= inner.end
        end

        # @param outer [Range<Integer>] The candidate enclosing range.
        # @param inner [Range<Integer>] The range that may be enclosed.
        # @return [Boolean] Whether `outer` encloses `inner` and spans more lines than it does.
        sig { params(outer: T::Range[Integer], inner: T::Range[Integer]).returns(T::Boolean) }
        def self.strictly_encloses?(outer, inner)
          encloses?(outer, inner) && line_count(outer) > line_count(inner)
        end

        sig { params(range: T::Range[Integer]).returns(Integer) }
        def self.line_count(range)
          range.end - range.begin
        end

        private_class_method :line_count
      end
    end
  end
end
