# typed: strict
# frozen_string_literal: true

module SimpleCov
  module Formatter
    class AIFormatter
      class MarkdownBuilder
        # Selects the files with coverage deficits, orders them lowest-coverage first and writes
        # each one's semantic-node fragments through the budget.
        class DeficitCompiler
          extend T::Sig

          # Header for the coverage deficits section
          HEADING = T.let("## Coverage Deficits\n\n", String)
          # Coverage criterion selector understood by simplecov >= 1.0's covered_percent.
          BRANCH_CRITERION = T.let(:branch, Symbol)

          sig { params(coverage_metrics: SimpleCov::Result, config: Configuration, builder: MarkdownBuilder).void }
          def initialize(coverage_metrics, config, builder)
            @coverage_metrics = coverage_metrics
            @config = config
            @builder = builder
            @method_coverage_measured = T.let(MethodDeficit.measured?(coverage_metrics), T::Boolean)
          end

          # Writes the deficit section through the budget, lowest-coverage files first, and
          # stops rendering once the budget closes the section.
          #
          # @param budget [ReportBudget] The budget every fragment is admitted through.
          # @return [Integer] The number of deficit files omitted or cut short.
          sig { params(budget: ReportBudget).returns(Integer) }
          def write_deficits(budget)
            writer = SectionWriter.new(budget, HEADING)
            deficit_files = find_deficit_files
            deficit_files.each do |file|
              break if writer.closed?

              writer.write_file_block(SectionWriter.file_heading(file), render_file(file))
            end
            deficit_files.size - writer.written_blocks
          end

          private

          sig { returns(T::Array[SimpleCov::SourceFile]) }
          def find_deficit_files
            files_with_deficits = @coverage_metrics.files.reject { |source_file| fully_covered?(source_file) }
            T.let(files_with_deficits.sort_by { |file| [file.covered_percent, file.filename] },
                  T::Array[SimpleCov::SourceFile])
          end

          # A file only counts as fully covered when every criterion SimpleCov measured for it
          # is perfect: lines, branches (when enabled) and methods (SimpleCov >= 1.0 with
          # `enable_coverage :method`; otherwise there are no methods to miss).
          sig { params(file: SimpleCov::SourceFile).returns(T::Boolean) }
          def fully_covered?(file)
            line_perfect?(file) && branch_perfect?(file) && method_deficits_of(file).empty?
          end

          # Method deficits count only when SimpleCov measured methods in this run (the header
          # then carries the method line too); otherwise stale `methods` entries are ignored.
          sig { params(file: SimpleCov::SourceFile).returns(T::Array[MethodDeficit]) }
          def method_deficits_of(file)
            @method_coverage_measured ? MethodDeficit.from_file(file) : []
          end

          sig { params(file: SimpleCov::SourceFile).returns(T::Boolean) }
          def line_perfect?(file)
            file.covered_percent >= Constants::PERFECT_COVERAGE_PERCENT
          end

          # SimpleCov reports 100% branch coverage for a file without branches, so a file only
          # fails this check when it has missed branches.
          sig { params(file: SimpleCov::SourceFile).returns(T::Boolean) }
          def branch_perfect?(file)
            branch_percent = branch_coverage_percent(file) || Constants::PERFECT_COVERAGE_PERCENT
            branch_percent >= Constants::PERFECT_COVERAGE_PERCENT
          end

          # Returns the file's branch coverage percentage, preferring simplecov >= 1.0's
          # non-deprecated `covered_percent(:branch)` and falling back to the older
          # `branches_coverage_percent` on simplecov < 1.0 (which does not accept a criterion).
          sig { params(file: SimpleCov::SourceFile).returns(T.nilable(Float)) }
          def branch_coverage_percent(file)
            file.covered_percent(BRANCH_CRITERION)
          rescue ArgumentError
            file.branches_coverage_percent
          end

          sig { params(file: SimpleCov::SourceFile).returns(T::Array[String]) }
          def render_file(file)
            formatter = DeficitFormatter.new(@config, SourceLines.of(file), BranchEnricher.enrich(file))
            nodes = @builder.try_resolve_ast(file.filename)
            method_deficits = method_deficits_of(file)
            return formatter.render_raw_fragments(file, method_deficits) unless nodes

            formatter.render_node_fragments(file, nodes, method_deficits)
          end
        end
      end
    end
  end
end
