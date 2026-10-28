# typed: strong
# frozen_string_literal: true

module SimpleCov
  module Formatter
    class AIFormatter
      class MarkdownBuilder
        # One global coverage percentage of the header: measured, not measured in this run (nil),
        # or undecodable ({UNDECODABLE_PERCENT}, NaN) when SimpleCov raised while computing it.
        class Figure
          extend T::Sig

          # Line-coverage label shown when line coverage was not enabled for the run (SimpleCov
          # >= 1.0 allows a branch- or method-only run)
          LINE_DISABLED_LABEL = 'N/A (line coverage not enabled)'
          # Branch-coverage label shown when branch coverage was not enabled for the run
          BRANCH_DISABLED_LABEL = 'N/A (branch coverage not enabled)'
          # Label shown for a figure SimpleCov could not compute from a corrupt resultset
          UNDECODABLE_LABEL = 'N/A (coverage data could not be decoded)'
          # Stands in for a figure SimpleCov raised on while decoding: not a number, so it never
          # compares as perfect and the status reads FAILED (typed as any figure's percentage)
          UNDECODABLE_PERCENT = T.let(Float::NAN, T.nilable(Float))
          # Percentages are printed with one decimal, floored (see #label)
          PERCENT_TEMPLATE = '%.1f%%'

          # Reads a percentage through the decode guard: SimpleCov computes its statistics for
          # every criterion at once, so one corrupt branch descriptor makes every figure
          # undecodable.
          #
          # @yieldreturn [Float, nil] The percentage, or nil when the criterion is not measured.
          # @return [Figure] The figure, {UNDECODABLE_PERCENT} when the block raised.
          sig { params(blk: T.proc.returns(T.nilable(Float))).returns(Figure) }
          def self.read(&blk)
            new(DecodeGuard.attempt(UNDECODABLE_PERCENT, &blk))
          end

          # @param covered [Integer, nil] The covered count; nil when not measured.
          # @param total [Integer, nil] The relevant count; nil when not measured.
          # @return [Float, nil] The covered share in percent (100.0 for nothing to cover), or nil
          #   when the criterion is not measured.
          sig { params(covered: T.nilable(Integer), total: T.nilable(Integer)).returns(T.nilable(Float)) }
          def self.ratio(covered, total)
            return nil unless covered && total
            return Constants::PERFECT_COVERAGE_PERCENT if total.zero?

            covered.fdiv(total) * Constants::PERFECT_COVERAGE_PERCENT
          end

          # @param percent [Float, nil] The percentage, nil when not measured.
          sig { params(percent: T.nilable(Float)).void }
          def initialize(percent)
            @percent = percent
          end

          # @return [Boolean] Whether the figure does not fail the run: it is unmeasured or at
          #   100%. An undecodable figure (NaN) compares as imperfect, so it fails it.
          sig { returns(T::Boolean) }
          def passing?
            percent = @percent
            percent ? percent >= Constants::PERFECT_COVERAGE_PERCENT : true
          end

          # One floored decimal, so a run at 99.96% never reads as 100.0% beside a FAILED status;
          # {UNDECODABLE_LABEL} for a figure SimpleCov could not compute.
          #
          # @return [String, nil] The label, or nil for an unmeasured figure.
          sig { returns(T.nilable(String)) }
          def label
            percent = @percent
            return nil unless percent

            percent.nan? ? UNDECODABLE_LABEL : format(PERCENT_TEMPLATE, percent.floor(1))
          end

          # @param template [String] A line with a `%<figure>s` placeholder for the label.
          # @return [String, nil] The line carrying the label, or nil for an unmeasured figure.
          sig { params(template: String).returns(T.nilable(String)) }
          def line(template)
            text = label
            text && format(template, figure: text)
          end
        end
      end
    end
  end
end
