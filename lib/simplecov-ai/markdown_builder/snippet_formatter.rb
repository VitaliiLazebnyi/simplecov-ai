# typed: strict
# frozen_string_literal: true

module SimpleCov
  module Formatter
    class AIFormatter
      class MarkdownBuilder
        # Handles extraction and formatting of source code snippets for the markdown digest.
        module SnippetFormatter
          extend T::Sig

          # Approximate maximum characters per line for truncation calculation
          ESTIMATED_CHARS_PER_LINE = T.let(80, Integer)
          # Suffix added to truncated snippets
          TRUNCATION_ELLIPSIS = T.let('...', String)
          # Template for identical snippet occurrences indicator
          OCCURRENCE_TEMPLATE = T.let('(Occurrence %d of %d).', String)

          # Extracts and normalizes exact string literals from the source file arrays.
          #
          # @param line_nums [Array<Integer>] Target line coordinates.
          # @param source_lines [Array<String>] The raw text lines of the file.
          # @return [String] Joined snippet text.
          sig { params(line_nums: T::Array[Integer], source_lines: T::Array[String]).returns(String) }
          def fetch_snippet_text(line_nums, source_lines)
            line_nums.select(&:positive?)
                     .filter_map { |line_number| source_lines[line_number - 1]&.strip }
                     .reject(&:empty?)
                     .join(' ')
          end

          # Extracts a byte range from a source line. SimpleCov reports branch columns as
          # byte offsets, so slicing on the byte representation and restoring the original
          # encoding keeps sub-line snippets correct for multibyte source.
          #
          # @param line_text [String] The full source line.
          # @param start_col [Integer] Inclusive start byte offset.
          # @param end_col [Integer] Exclusive end byte offset.
          # @return [String, nil] The decoded slice, or nil if the range exceeds the line.
          sig { params(line_text: String, start_col: Integer, end_col: Integer).returns(T.nilable(String)) }
          def byte_slice(line_text, start_col, end_col)
            bytes = line_text.b
            return nil unless bytes.length >= end_col

            slice = bytes[start_col...end_col].to_s
            slice.force_encoding(line_text.encoding)
            slice.valid_encoding? ? slice : slice.scrub
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

          # Extracts the source text for a branch, preferring the exact inline sub-snippet when
          # column data is available and falling back to the full line range otherwise.
          #
          # @param branch [SimpleCov::SourceFile::Branch] The missed branch.
          # @param source_lines [Array<String>] Raw file contents.
          # @param columns [Array(Integer, Integer), nil] The branch's `[start_col, end_col]`
          #   byte offsets from {BranchEnricher}, when SimpleCov's raw data provided them.
          # @return [String] The branch's source snippet.
          sig do
            params(branch: SimpleCov::SourceFile::Branch, source_lines: T::Array[String],
                   columns: T.nilable([Integer, Integer])).returns(String)
          end
          def extract_branch_text(branch, source_lines, columns)
            inline_text = extract_inline_branch(branch, columns, source_lines)
            return inline_text if inline_text

            fetch_snippet_text((branch.start_line..branch.end_line).to_a, source_lines)
          end

          # The exact sub-line expression of a single-line branch, or nil when the branch spans
          # several lines, has no column data or its columns fall outside the source line.
          #
          # @param branch [SimpleCov::SourceFile::Branch] The missed branch.
          # @param columns [Array(Integer, Integer), nil] The branch's byte offsets, if known.
          # @param source_lines [Array<String>] Raw file contents.
          # @return [String, nil] The stripped inline expression.
          sig do
            params(branch: SimpleCov::SourceFile::Branch, columns: T.nilable([Integer, Integer]),
                   source_lines: T::Array[String]).returns(T.nilable(String))
          end
          def extract_inline_branch(branch, columns, source_lines)
            return nil unless columns && branch.start_line == branch.end_line

            line_text = source_lines[branch.start_line - 1]
            return nil unless line_text

            start_col, end_col = columns
            byte_slice(line_text, start_col, end_col)&.strip
          end

          # The first non-empty source line of a branch's range, for arms that are cut short.
          #
          # @param branch [SimpleCov::SourceFile::Branch] The missed branch.
          # @param source_lines [Array<String>] Raw file contents.
          # @return [String] The stripped first line, or an empty string when the range is blank.
          sig { params(branch: SimpleCov::SourceFile::Branch, source_lines: T::Array[String]).returns(String) }
          def first_source_line(branch, source_lines)
            (branch.start_line..branch.end_line).lazy
                                                .map { |line_number| fetch_snippet_text([line_number], source_lines) }
                                                .find { |text| !text.empty? }
                                                .to_s
          end

          # Labels a line range the way deficits are tagged: `12` for one line, `12-15` for a span.
          #
          # @param start_line [Integer] The first line.
          # @param end_line [Integer] The last line.
          # @return [String] The label without the `L` prefix.
          sig { params(start_line: Integer, end_line: Integer).returns(String) }
          def line_label(start_line, end_line)
            start_line == end_line ? start_line.to_s : "#{start_line}-#{end_line}"
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

            snippet = source_lines[line_num - 1]&.strip
            return '' if snippet.nil? || snippet.empty?

            positions = occurrence_index(node, source_lines)[snippet] || []
            return '' unless positions.size > 1

            Kernel.format(OCCURRENCE_TEMPLATE, positions.index(line_num).to_i + 1, positions.size)
          end

          # Builds (once per node) a map of stripped line text to the line numbers where it
          # occurs within the node, so occurrence disambiguation is O(node span) instead of
          # O(deficits × node span). Results are memoized on the including formatter instance.
          sig do
            params(node: ASTResolver::SemanticNode, source_lines: T::Array[String])
              .returns(T::Hash[String, T::Array[Integer]])
          end
          def occurrence_index(node, source_lines)
            cache = (@occurrence_index ||= T.let(
              {}.compare_by_identity,
              T.nilable(T::Hash[ASTResolver::SemanticNode, T::Hash[String, T::Array[Integer]]])
            ))
            cache[node] ||= build_occurrence_index(node, source_lines)
          end

          sig do
            params(node: ASTResolver::SemanticNode, source_lines: T::Array[String])
              .returns(T::Hash[String, T::Array[Integer]])
          end
          def build_occurrence_index(node, source_lines)
            index = T.let({}, T::Hash[String, T::Array[Integer]])
            (node.start_line..node.end_line).each do |line_number|
              content = source_lines[line_number - 1]&.strip
              next if content.nil? || content.empty?

              (index[content] ||= []) << line_number
            end
            index
          end
        end
      end
    end
  end
end
