# typed: strict
# frozen_string_literal: true

module SimpleCov
  module Formatter
    class AIFormatter
      class MarkdownBuilder
        # Iterates through files with coverage deficits and coordinates their AST parsing and snippet generation.
        class DeficitCompiler
          extend T::Sig

          # Header for the coverage deficits section
          HEADING = T.let("## Coverage Deficits\n\n", String)
          # Template for file-level deficit headings
          FILE_HEADING_TEMPLATE = T.let('### `%s`', String)
          # Coverage criterion selector understood by simplecov >= 1.0's covered_percent.
          BRANCH_CRITERION = T.let(:branch, Symbol)

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
              process_file(buffer, file)
              @builder.record_truncation!
              break if @builder.truncated?
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
            branch_coverage_perfect?(branch_coverage_percent(file))
          end

          # Returns the file's branch coverage percentage, preferring simplecov >= 1.0's
          # non-deprecated `covered_percent(:branch)` and falling back to the older
          # `branches_coverage_percent` on simplecov < 1.0 (which does not accept a criterion).
          sig { params(file: SimpleCov::SourceFile).returns(T.nilable(Numeric)) }
          def branch_coverage_percent(file)
            file.covered_percent(BRANCH_CRITERION)
          rescue ArgumentError
            file.respond_to?(:branches_coverage_percent) ? file.branches_coverage_percent : nil
          end

          sig { params(coverage: T.nilable(Numeric)).returns(T::Boolean) }
          def branch_coverage_perfect?(coverage)
            return true if coverage.nil?

            coverage >= Constants::PERFECT_COVERAGE_PERCENT
          end

          sig { params(buffer: StringIO, file: SimpleCov::SourceFile).void }
          def process_file(buffer, file)
            BranchEnricher.enrich(file)
            buffer.puts format(FILE_HEADING_TEMPLATE, file.project_filename.delete_prefix('/'))

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
            # Scrub invalid byte sequences so a file with non-UTF-8 content cannot raise
            # Encoding::CompatibilityError when its snippets are later stripped and joined.
            File.readlines(filename).map(&:scrub)
          rescue StandardError
            []
          end
        end
      end
    end
  end
end
