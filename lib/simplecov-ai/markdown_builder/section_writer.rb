# typed: strict
# frozen_string_literal: true

module SimpleCov
  module Formatter
    class AIFormatter
      class MarkdownBuilder
        # Writes one report section (`## Coverage Deficits`, `## Ignored Coverage Bypasses`)
        # through the {ReportBudget} at semantic-node granularity. The section heading travels
        # with the first file block so a heading never stands without content; each file block
        # is its heading plus one fragment per node, admitted one at a time, so truncation loses
        # at most the tail of a single file. Once a fragment is rejected the section closes and
        # later files are counted as omitted, which keeps the "lowest-coverage files first"
        # ordering promise intact.
        class SectionWriter
          extend T::Sig

          # Template for file-level headings in both sections
          FILE_HEADING_TEMPLATE = T.let('### %s', String)

          # @return [Integer] The number of file blocks written in full.
          sig { returns(Integer) }
          attr_reader :written_blocks

          # @param budget [ReportBudget] The budget every fragment is admitted through.
          # @param heading [String] The section heading, emitted with the first file block.
          sig { params(budget: ReportBudget, heading: String).void }
          def initialize(budget, heading)
            @budget = budget
            @heading = heading
            @heading_pending = T.let(true, T::Boolean)
            @closed = T.let(false, T::Boolean)
            @written_blocks = T.let(0, Integer)
          end

          # Renders the heading line of a file block from the file's project-relative path.
          #
          # @param file [SimpleCov::SourceFile] The file the block describes.
          # @return [String] The `### ` heading with the path inside a code span.
          sig { params(file: SimpleCov::SourceFile).returns(String) }
          def self.file_heading(file)
            format(FILE_HEADING_TEMPLATE, InlineCode.span(file.project_filename.delete_prefix('/')))
          end

          # @return [Boolean] Whether the budget has stopped this section.
          sig { returns(T::Boolean) }
          def closed?
            @closed
          end

          # Writes a file block: the heading together with the first node fragment, then each
          # further fragment while the budget admits it. A block the budget stops is not
          # counted in {#written_blocks}.
          #
          # @param file_heading [String] The `### ` heading line of the block.
          # @param node_fragments [Array<String>] One Markdown fragment per semantic node.
          # @return [void]
          sig { params(file_heading: String, node_fragments: T::Array[String]).void }
          def write_file_block(file_heading, node_fragments)
            return if @closed

            first_fragment, *further_fragments = node_fragments
            opening = "#{@heading if @heading_pending}#{file_heading}\n#{first_fragment}"
            return close!(block_started: false) unless @budget.admit(opening)

            @heading_pending = false
            return close!(block_started: true) unless further_fragments.all? { |fragment| @budget.admit(fragment) }

            @budget.write("\n")
            @written_blocks += 1
          end

          private

          # Closes the section. A block cut short still gets its trailing blank line so the next
          # section starts on a fresh paragraph.
          sig { params(block_started: T::Boolean).void }
          def close!(block_started:)
            @budget.write("\n") if block_started
            @closed = true
          end
        end
      end
    end
  end
end
