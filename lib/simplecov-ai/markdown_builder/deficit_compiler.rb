# typed: strong
# frozen_string_literal: true

module SimpleCov
  module Formatter
    class AIFormatter
      class MarkdownBuilder
        # Selects the files with coverage deficits, orders them lowest-coverage first and writes
        # each one's semantic-node fragments through the budget. A file whose coverage data
        # SimpleCov cannot decode counts as a deficit file: it is listed first of all, and its
        # only entry is the error line the decode guard produces.
        class DeficitCompiler
          extend T::Sig

          # Header for the coverage deficits section
          HEADING = "## Coverage Deficits\n\n"
          # Sort figure of a file whose coverage SimpleCov cannot decode: below any real
          # percentage, so the file precedes every decodable deficit file.
          UNDECODABLE_COVERAGE = -1.0

          # Orders deficit files lowest-coverage first, by path among equals; a file whose
          # coverage SimpleCov cannot decode sorts as {UNDECODABLE_COVERAGE}, first of all.
          #
          # @api private
          # @param file [SimpleCov::SourceFile] A deficit file.
          # @return [Array(Float, String)] The sort key.
          sig { params(file: SimpleCov::SourceFile).returns([Float, String]) }
          def self.sort_key(file)
            [DecodeGuard.attempt(UNDECODABLE_COVERAGE) { file.covered_percent }, file.filename]
          end

          # A file only counts as fully covered when every criterion SimpleCov measured for it
          # is perfect, by SimpleCov's own verdicts: no missed line, no missed branch (there are
          # none when branch coverage is off, and skipped ones do not count) and no missed
          # method (SimpleCov >= 1.0 with `enable_coverage :method`; otherwise there are no
          # methods to miss).
          #
          # @api private
          # @param file [SimpleCov::SourceFile] The file to judge.
          # @param method_deficits [Array<MethodDeficit>] Its never-invoked methods, when counted.
          # @return [Boolean] Whether nothing in the file is missed.
          sig { params(file: SimpleCov::SourceFile, method_deficits: T::Array[MethodDeficit]).returns(T::Boolean) }
          def self.fully_covered?(file, method_deficits)
            file.missed_lines.empty? && file.missed_branches.empty? && method_deficits.empty?
          end

          sig { params(coverage_metrics: SimpleCov::Result, config: Configuration, builder: MarkdownBuilder).void }
          def initialize(coverage_metrics, config, builder)
            @coverage_metrics = coverage_metrics
            @config = config
            @builder = builder
            # When the aggregate cannot be decoded the answer is unknowable; the header then shows
            # an N/A method line, matched here by listing the method deficits of every file that
            # still decodes.
            measured = DecodeGuard.attempt(true) { MethodDeficit.measured?(coverage_metrics) }
            @method_coverage_measured = T.let(measured, T::Boolean)
          end

          # Writes the deficit section through the budget, lowest-coverage files first, and
          # stops rendering once the budget closes the section.
          #
          # @param budget [ReportBudget] The budget every fragment is admitted through.
          # @return [Integer] The number of deficit files omitted or cut short.
          sig { params(budget: ReportBudget).returns(Integer) }
          def write_deficits(budget)
            SectionWriter.new(budget, HEADING).write_files(find_deficit_files) { |file| render_file(file) }
          end

          private

          sig { returns(T::Array[SimpleCov::SourceFile]) }
          def find_deficit_files
            deficit_files = @coverage_metrics.files.select { |file| deficit?(file) }
            deficit_files.sort_by { |file| DeficitCompiler.sort_key(file) }
          end

          # A file with a missed line, branch or method — or one whose data SimpleCov cannot
          # decode, whose entry is the error line {#render_file} produces.
          sig { params(file: SimpleCov::SourceFile).returns(T::Boolean) }
          def deficit?(file)
            DecodeGuard.attempt(true) { !DeficitCompiler.fully_covered?(file, method_deficits_of(file)) }
          end

          # Method deficits count only when SimpleCov measured methods in this run (the header
          # then carries the method line too); otherwise stale `methods` entries are ignored.
          sig { params(file: SimpleCov::SourceFile).returns(T::Array[MethodDeficit]) }
          def method_deficits_of(file)
            @method_coverage_measured ? MethodDeficit.from_file(file) : []
          end

          # The file's fragments, or the single error entry when SimpleCov raises while it
          # materialises the file's lines, branches or methods.
          sig { params(file: SimpleCov::SourceFile).returns(T::Array[String]) }
          def render_file(file)
            DecodeGuard.render do
              DeficitFormatter.new(@config, SourceLines.of(file), BranchEnricher.enrich(file))
                              .render(file, @builder.try_resolve_ast(file.filename), method_deficits_of(file))
            end
          end
        end
      end
    end
  end
end
