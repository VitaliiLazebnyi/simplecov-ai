# typed: strict
# frozen_string_literal: true

module SimpleCov
  module Formatter
    class AIFormatter
      class MarkdownBuilder
        # Iterates through files with coverage deficits and coordinates their AST parsing and snippet generation.
        class DeficitCompiler
          extend T::Sig
          include SnippetFormatter

          # Header for the coverage deficits section
          HEADING = T.let("## Coverage Deficits\n\n", String)
          # Template for file-level deficit headings
          FILE_HEADING_TEMPLATE = T.let('### `%s`', String)
          # Error message for AST parsing failures
          ERROR_AST_FAILED = T.let("  - **ERROR:** AST Parsing Failed. Showing raw line numbers instead.\n", String)
          # Template for node-level deficit headings
          NODE_HEADING_TEMPLATE = T.let('- `%s`', String)
          # Coarse-grained deficit summary message
          DEFICIT_COARSE = T.let('  - **Deficit:** Contains unexecuted lines or branches.', String)
          # Template for a specific line deficit
          LINE_DEFICIT_TEMPLATE = T.let('  - **Line Deficit:** [L%d] `%s` %s', String)
          # Template for a specific branch deficit
          BRANCH_DEFICIT_TEMPLATE = T.let('  - **Branch Deficit:** [L%s] Missing coverage for `%s` branch: `%s` %s',
                                          String)

          sig { params(coverage_metrics: SimpleCov::Result, config: Configuration, builder: MarkdownBuilder).void }
          def initialize(coverage_metrics, config, builder)
            @coverage_metrics = coverage_metrics
            @config = config
            @builder = builder
          end

          sig { params(buffer: StringIO).void }
          def write_deficits(buffer)
            files = find_deficit_files
            return if files.empty?

            buffer.puts HEADING
            files.each do |file|
              break if @builder.truncate_if_needed?

              process_file(buffer, file)
            end
          end

          private

          sig { returns(T::Array[SimpleCov::SourceFile]) }
          def find_deficit_files
            files_with_deficits = @coverage_metrics.files.reject do |f|
              line_perfect?(f) && branch_perfect?(f)
            end
            T.let(files_with_deficits.sort_by { |file| [file.covered_percent, file.filename] }, T::Array[SimpleCov::SourceFile])
          end

          sig { params(file: SimpleCov::SourceFile).returns(T::Boolean) }
          def line_perfect?(file)
            file.covered_percent >= Constants::PERFECT_COVERAGE_PERCENT
          end

          sig { params(file: SimpleCov::SourceFile).returns(T::Boolean) }
          def branch_perfect?(file)
            cov = file.respond_to?(:branches_coverage_percent) ? file.branches_coverage_percent : nil
            branch_coverage_perfect?(cov)
          end

          sig { params(coverage: T.nilable(BasicObject)).returns(T::Boolean) }
          def branch_coverage_perfect?(coverage)
            case coverage
            when Float, Integer
              coverage >= Constants::PERFECT_COVERAGE_PERCENT
            else
              case coverage
              when nil then true
              else false
              end
            end
          end

          sig { params(buffer: StringIO, file: SimpleCov::SourceFile).void }
          def process_file(buffer, file)
            BranchEnricher.enrich(file)
            buffer.puts format(FILE_HEADING_TEMPLATE, file.project_filename)

            formatter = DeficitFormatter.new(buffer, @config)
            nodes = @builder.try_resolve_ast(file.filename)

            if nodes
              formatter.process_deficits(file, nodes, -> { safe_readlines(file.filename) })
            else
              formatter.format_raw_deficits(file, safe_readlines(file.filename))
            end
          end

          sig { params(filename: String).returns(T::Array[String]) }
          def safe_readlines(filename)
            File.readlines(filename)
          rescue StandardError
            []
          end
        end
      end
    end
  end
end
