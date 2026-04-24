# typed: strict
# frozen_string_literal: true

module SimpleCov
  module Formatter
    class AIFormatter
      class MarkdownBuilder
        # Handles extraction and formatting of source code snippets for the markdown digest.
        module SnippetFormatter
          extend T::Sig

          ESTIMATED_CHARS_PER_LINE = T.let(80, Integer)
          TRUNCATION_ELLIPSIS = T.let('...', String)
          OCCURRENCE_TEMPLATE = T.let('(Occurrence %d of %d).', String)

          # Extracts and normalizes exact string literals from the source file arrays.
          #
          # @param line_nums [Array<Integer>] Target line coordinates.
          # @param source_lines [Array<String>] The raw text lines of the file.
          # @return [String] Joined snippet text.
          sig { params(line_nums: T::Array[Integer], source_lines: T::Array[String]).returns(String) }
          def fetch_snippet_text(line_nums, source_lines)
            line_nums.filter_map { |line_number| source_lines[line_number - 1]&.strip }.reject(&:empty?).join(' ')
          end

          # Safely limits the character length of a code snippet according to global configurations.
          #
          # @param snippet_text [String] The snippet to potentially truncate.
          # @param max_snippet_lines [Integer] The configured max lines.
          # @return [String] Truncated string with trailing ellipses if limit exceeded.
          sig { params(snippet_text: String, max_snippet_lines: Integer).returns(String) }
          def truncate_snippet(snippet_text, max_snippet_lines)
            max_chars = max_snippet_lines * ESTIMATED_CHARS_PER_LINE
            if snippet_text.length > max_chars
              "#{snippet_text[0...max_chars]}#{TRUNCATION_ELLIPSIS}"
            else
              snippet_text
            end
          end

          # Disambiguates identical code snippets within the same semantic block (e.g., "(Occurrence 2 of 3)").
          #
          # @param line_num [Integer] The target coordinate of the deficit.
          # @param source_lines [Array<String>] Raw file contents.
          # @param node [ASTResolver::SemanticNode, nil] The semantic node boundary to search within.
          # @return [String] Occurrence label or empty string if unique.
          sig do
            params(line_num: Integer, source_lines: T::Array[String],
                   node: T.nilable(ASTResolver::SemanticNode)).returns(String)
          end
          def calculate_occurrence(line_num, source_lines, node)
            return '' if node.nil?

            first_line_of_snippet = source_lines[line_num - 1]&.strip
            return '' if first_line_of_snippet.nil? || first_line_of_snippet.empty?

            occurrences, current = count_snippet_occurrences(first_line_of_snippet, line_num, source_lines, node)

            occurrences > 1 ? Kernel.format(OCCURRENCE_TEMPLATE, current, occurrences) : ''
          end

          sig do
            params(snippet: String, target_line_number: Integer, source_lines: T::Array[String],
                   node: ASTResolver::SemanticNode).returns([Integer, Integer])
          end
          def count_snippet_occurrences(snippet, target_line_number, source_lines, node)
            occurrences = 0
            current_occurrence = 1

            (node.start_line..node.end_line).each do |line_number|
              line_content = source_lines[line_number - 1]&.strip
              next unless line_content == snippet

              occurrences += 1
              current_occurrence = occurrences if line_number == target_line_number
            end

            [occurrences, current_occurrence]
          end
        end
      end
    end
  end
end
