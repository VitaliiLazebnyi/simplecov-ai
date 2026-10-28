# typed: strong
# frozen_string_literal: true

module SimpleCov
  module Formatter
    class AIFormatter
      # Inclusive source-line ranges: the span of anything with a first and a last line, the
      # containment predicates shared by bypass attribution (skip regions against semantic nodes),
      # deficit grouping and branch rendering (arms against sibling arms), and the `[L…]` labels.
      module LineSpan
        extend T::Sig

        # Anything that spans source lines.
        Spanning = T.type_alias do
          T.any(SimpleCov::SourceFile::Branch, ASTResolver::SemanticNode, MarkdownBuilder::MethodDeficit)
        end

        # @param spanning [SimpleCov::SourceFile::Branch, ASTResolver::SemanticNode,
        #   MarkdownBuilder::MethodDeficit] A branch, node or method deficit.
        # @return [Range<Integer>] The lines from its first to its last.
        sig { params(spanning: Spanning).returns(T::Range[Integer]) }
        def self.of(spanning)
          spanning.start_line..spanning.end_line
        end

        # @param line_number [Integer] A line.
        # @return [Range<Integer>] The range of that one line.
        sig { params(line_number: Integer).returns(T::Range[Integer]) }
        def self.line(line_number)
          line_number..line_number
        end

        # @param outer [Range<Integer>] The candidate enclosing range.
        # @param inner [Range<Integer>] The range that may be enclosed.
        # @return [Boolean] Whether every line of `inner` lies within `outer`.
        sig { params(outer: T::Range[Integer], inner: T::Range[Integer]).returns(T::Boolean) }
        def self.encloses?(outer, inner)
          outer.cover?(inner)
        end

        # @param outer [Range<Integer>] The candidate enclosing range.
        # @param inner [Range<Integer>] The range that may be enclosed.
        # @return [Boolean] Whether `outer` encloses `inner` and spans more lines than it does.
        sig { params(outer: T::Range[Integer], inner: T::Range[Integer]).returns(T::Boolean) }
        def self.strictly_encloses?(outer, inner)
          encloses?(outer, inner) && !encloses?(inner, outer)
        end

        # Labels a range the way deficits are tagged: `12` for one line, `12-15` for a span.
        #
        # @param range [Range<Integer>] The lines.
        # @return [String] The label without the `L` prefix.
        sig { params(range: T::Range[Integer]).returns(String) }
        def self.label(range)
          first = range.begin
          last = range.end
          first == last ? first.to_s : "#{first}-#{last}"
        end

        # Orders ranges by first line, then wider ranges first, so an enclosing range precedes
        # the ones opening on its first line.
        #
        # @param range [Range<Integer>] The lines.
        # @return [Array(Integer, Integer)] The sort key.
        sig { params(range: T::Range[Integer]).returns([Integer, Integer]) }
        def self.sort_key(range)
          [range.begin, -range.end]
        end
      end
    end
  end
end
