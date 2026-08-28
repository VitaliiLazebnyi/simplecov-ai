# typed: strict
# frozen_string_literal: true

module SimpleCov
  module Formatter
    class AIFormatter
      class MarkdownBuilder
        # Renders text as a CommonMark code span. The backtick fence is one longer than the
        # longest backtick run inside the text, and the content is space-padded when it starts
        # or ends with a backtick, so a backtick in a snippet, comment, path or method name
        # (`def `(cmd)`) can never close the span early and let the remainder render as Markdown.
        module InlineCode
          extend T::Sig

          # @param text [String] The literal text to show verbatim.
          # @return [String] The text wrapped in a code span that is safe for any content.
          sig { params(text: String).returns(String) }
          def self.span(text)
            fence = '`' * ((text.scan(/`+/).map(&:length).max || 0) + 1)
            content = text.start_with?('`') || text.end_with?('`') ? " #{text} " : text
            "#{fence}#{content}#{fence}"
          end
        end
      end
    end
  end
end
