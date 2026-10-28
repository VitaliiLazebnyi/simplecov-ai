# typed: strong
# frozen_string_literal: true

module SimpleCov
  module Formatter
    class AIFormatter
      class MarkdownBuilder
        # Extracts and formats the source snippets of one file for the markdown digest.
        class SnippetFormatter
          extend T::Sig

          # Approximate maximum characters per line for truncation calculation
          ESTIMATED_CHARS_PER_LINE = 80
          # Suffix added to truncated snippets
          TRUNCATION_ELLIPSIS = '...'
          # Template for identical snippet occurrences indicator
          OCCURRENCE_TEMPLATE = '(Occurrence %d of %d).'
          # The stripped text of every non-blank line, by line number.
          TextsByLine = T.type_alias { T::Hash[Integer, String] }
          # Per node (nodes compare by identity), the lines holding each text; nil for blank lines.
          OccurrenceIndexes = T.type_alias do
            T::Hash[ASTResolver::SemanticNode, T::Hash[T.nilable(String), T::Array[Integer]]]
          end

          # Extracts a byte range from a source line. SimpleCov reports branch columns as
          # byte offsets, so slicing on the byte representation and restoring the original
          # encoding keeps sub-line snippets correct for multibyte source; a slice that cuts a
          # multibyte character is scrubbed.
          #
          # @param line_text [String] The full source line.
          # @param start_col [Integer] Inclusive start byte offset.
          # @param end_col [Integer] Exclusive end byte offset.
          # @return [String, nil] The decoded slice, stripped, or nil if the range exceeds the line.
          sig { params(line_text: String, start_col: Integer, end_col: Integer).returns(T.nilable(String)) }
          def self.byte_slice(line_text, start_col, end_col)
            bytes = line_text.b
            return nil if bytes.length < end_col

            slice = bytes[start_col...end_col]
            slice ? slice.force_encoding(line_text.encoding).scrub.strip : ''
          end

          # @param positions [Array<Integer>] The lines, in order, holding the same text.
          # @param line_number [Integer] The one of them to label.
          # @return [String] `(Occurrence N of M).`, or an empty string for a unique line.
          sig { params(positions: T::Array[Integer], line_number: Integer).returns(String) }
          def self.occurrence_label(positions, line_number)
            count = positions.size
            count > 1 ? format(OCCURRENCE_TEMPLATE, positions.count { |line| line <= line_number }, count) : ''
          end

          # @param source_lines [Array<String>] The raw text lines of a file.
          # @return [Hash{Integer => String}] The stripped text of every non-blank line, by
          #   1-based line number.
          sig { params(source_lines: T::Array[String]).returns(T::Hash[Integer, String]) }
          def self.texts_by_line(source_lines)
            source_lines.each.with_index(1).to_h { |line, line_number| [line_number, line.strip] }
                        .reject { |_line_number, stripped| stripped.empty? }
          end

          # The exact sub-line expression of a single-line branch, or nil when the branch spans
          # several lines, has no column data or its columns fall outside the source line.
          #
          # @param source_lines [Array<String>] The raw text lines of the file.
          # @param range [Range<Integer>] The lines of the branch.
          # @param columns [Array(Integer, Integer), nil] The branch's byte offsets, if known.
          # @return [String, nil] The stripped inline expression.
          sig do
            params(source_lines: T::Array[String], range: T::Range[Integer], columns: T.nilable([Integer, Integer]))
              .returns(T.nilable(String))
          end
          def self.inline_slice(source_lines, range, columns)
            first_line = range.begin
            source_line = source_lines.at(first_line - 1)
            return nil unless columns && source_line && first_line == range.end

            byte_slice(source_line, *columns)
          end

          # @param source_lines [Array<String>] The raw text lines of the file.
          # @param max_snippet_lines [Integer] The configured snippet ceiling, in lines.
          sig { params(source_lines: T::Array[String], max_snippet_lines: Integer).void }
          def initialize(source_lines, max_snippet_lines)
            @source_lines = source_lines
            @texts_by_line = T.let(SnippetFormatter.texts_by_line(source_lines), TextsByLine)
            @max_chars = T.let(max_snippet_lines * ESTIMATED_CHARS_PER_LINE, Integer)
            @occurrence_indexes = T.let({}, OccurrenceIndexes)
          end

          # Extracts and normalizes the exact text of source lines.
          #
          # @param line_numbers [Array<Integer>, Range<Integer>] Target line coordinates.
          # @return [String] The stripped non-empty lines, joined by spaces; lines outside the file
          #   are left out.
          sig { params(line_numbers: T::Enumerable[Integer]).returns(String) }
          def text(line_numbers)
            line_numbers.filter_map { |line_number| line_text(line_number) }.join(' ')
          end

          # Safely limits the character length of a code snippet according to the configuration.
          #
          # @param snippet_text [String] The snippet to potentially truncate.
          # @return [String] Truncated string with trailing ellipses if limit exceeded.
          sig { params(snippet_text: String).returns(String) }
          def truncate(snippet_text)
            snippet_text.length > @max_chars ? "#{snippet_text[0, @max_chars]}#{TRUNCATION_ELLIPSIS}" : snippet_text
          end

          # The source text for a branch, preferring the exact inline sub-snippet when column
          # data is available and falling back to the full line range otherwise.
          #
          # @param branch [SimpleCov::SourceFile::Branch] The missed branch.
          # @param columns [Array(Integer, Integer), nil] The branch's `[start_col, end_col]`
          #   byte offsets from {BranchEnricher}, when SimpleCov's raw data provided them.
          # @return [String] The branch's source snippet.
          sig { params(branch: SimpleCov::SourceFile::Branch, columns: T.nilable([Integer, Integer])).returns(String) }
          def branch_text(branch, columns)
            range = LineSpan.of(branch)
            SnippetFormatter.inline_slice(@source_lines, range, columns) || text(range)
          end

          # The first non-empty source line of a range followed by an ellipsis, for arms that
          # are cut short.
          #
          # @param range [Range<Integer>] The lines of the arm.
          # @return [String] The stripped first line (empty when the range is blank) and `...`.
          sig { params(range: T::Range[Integer]).returns(String) }
          def cut(range)
            "#{range.filter_map { |line_number| line_text(line_number) }.first}#{TRUNCATION_ELLIPSIS}"
          end

          # Disambiguates identical code snippets within the same semantic block (e.g., "(Occurrence 2 of 3)").
          #
          # @param line_number [Integer] The target coordinate of the deficit.
          # @param node [ASTResolver::SemanticNode, nil] The semantic node boundary to search within.
          # @return [String] Occurrence label or empty string if unique.
          sig { params(line_number: Integer, node: T.nilable(ASTResolver::SemanticNode)).returns(String) }
          def occurrence(line_number, node)
            text = line_text(line_number)
            SnippetFormatter.occurrence_label((node && text && occurrence_index(node)[text]) || [], line_number)
          end

          private

          # @return [String, nil] The stripped text of the line; nil for a line outside the file
          #   or one with no text.
          sig { params(line_number: Integer).returns(T.nilable(String)) }
          def line_text(line_number)
            @texts_by_line[line_number]
          end

          # A map, built once per node, of stripped line text to the line numbers where it occurs
          # within the node, so occurrence disambiguation is O(node span) instead of
          # O(deficits × node span). Blank lines (and lines past the end of the file) are grouped
          # under nil, which no snippet looks up, so a blank snippet never has an occurrence.
          sig { params(node: ASTResolver::SemanticNode).returns(T::Hash[T.nilable(String), T::Array[Integer]]) }
          def occurrence_index(node)
            @occurrence_indexes[node] ||= node.line_range.group_by { |line_number| line_text(line_number) }
          end
        end
      end
    end
  end
end
