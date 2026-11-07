# typed: strong
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
          FILE_HEADING_TEMPLATE = '### %s'
          # The section heading while it is still to be written with the first block; empty after.
          Headings = T.type_alias { T::Array[String] }

          # Renders the heading line of a file block from the file's project-relative path.
          #
          # @param file [SimpleCov::SourceFile] The file the block describes.
          # @return [String] The `### ` heading with the path inside a code span.
          sig { params(file: SimpleCov::SourceFile).returns(String) }
          def self.file_heading(file)
            format(FILE_HEADING_TEMPLATE, InlineCode.span(file.project_filename.delete_prefix('/')))
          end

          # @param budget [ReportBudget] The budget every fragment is admitted through.
          # @param heading [String] The section heading, emitted with the first file block.
          sig { params(budget: ReportBudget, heading: String).void }
          def initialize(budget, heading)
            @budget = budget
            @pending_headings = T.let([heading], Headings)
            # Blocks written in full, and blocks attempted: both start at zero.
            @written_blocks = T.let(0, Integer)
            @attempted_blocks = T.let(@written_blocks, Integer)
          end

          # Writes a block per file, lowest-coverage first, rendering each file only while the
          # section is still open.
          #
          # @param files [Array<SimpleCov::SourceFile>] The files, in report order.
          # @yieldparam file [SimpleCov::SourceFile] A file to render.
          # @yieldreturn [Array<String>] Its node fragments.
          # @return [Integer] The number of files omitted or cut short.
          sig do
            params(files: T::Array[SimpleCov::SourceFile],
                   blk: T.proc.params(file: SimpleCov::SourceFile).returns(T::Array[String])).returns(Integer)
          end
          def write_files(files, &blk)
            files.each do |file|
              break if closed?

              write_file_block(SectionWriter.file_heading(file), yield(file))
            end
            files.size - @written_blocks
          end

          # Writes rendered file blocks in order.
          #
          # @param blocks [Array<Array(String, Array<String>)>] Each file's heading and node fragments.
          # @return [Integer] The number of blocks omitted or cut short.
          sig { params(blocks: T::Array[[String, T::Array[String]]]).returns(Integer) }
          def write_blocks(blocks)
            blocks.each { |file_heading, node_fragments| write_file_block(file_heading, node_fragments) }
            blocks.size - @written_blocks
          end

          private

          # A section closes at the first block the budget stops: every block attempted before
          # it was written in full.
          sig { returns(T::Boolean) }
          def closed?
            @attempted_blocks > @written_blocks
          end

          # Writes a file block: the heading together with the first node fragment, then each
          # further fragment while the budget admits it. A block the budget stops is not counted
          # as written, and closes the section.
          #
          # @param file_heading [String] The `### ` heading line of the file.
          # @param node_fragments [Array<String>] One fragment per semantic node, in order.
          # @return [void]
          sig { params(file_heading: String, node_fragments: T::Array[String]).void }
          def write_file_block(file_heading, node_fragments)
            return if closed?

            @attempted_blocks += 1
            first_fragment, *further_fragments = node_fragments
            complete = @budget.admit("#{@pending_headings.join}#{file_heading}\n#{first_fragment}") &&
                       write_further(further_fragments)
            @written_blocks += 1 if complete
          end

          # Writes the fragments after an admitted opening while the budget admits them, then
          # the block's trailing blank line, which a block cut short gets too so the next
          # section starts on a fresh paragraph.
          sig { params(fragments: T::Array[String]).returns(T::Boolean) }
          def write_further(fragments)
            @pending_headings.clear
            complete = fragments.all? { |fragment| @budget.admit(fragment) }
            @budget.write("\n")
            complete
          end
        end
      end
    end
  end
end
