# typed: strict
# frozen_string_literal: true

module SimpleCov
  module Formatter
    class AIFormatter
      class MarkdownBuilder
        # Reads a file's source through the SourceFile SimpleCov already loaded — honouring the
        # shebang and encoding magic comment and transcoding to UTF-8 — instead of re-reading
        # the file from disk. Invalid byte sequences (which SimpleCov < 1.0 leaves in place) are
        # scrubbed so snippets can be stripped and joined without raising.
        module SourceLines
          extend T::Sig

          # @param file [SimpleCov::SourceFile] The file whose source is needed.
          # @return [Array<String>] The source lines (trailing newlines included), or an empty
          #   array when the source cannot be read.
          sig { params(file: SimpleCov::SourceFile).returns(T::Array[String]) }
          def self.of(file)
            file.src.map(&:scrub)
          rescue StandardError
            []
          end
        end
      end
    end
  end
end
