# typed: strong
# frozen_string_literal: true

module SimpleCov
  module Formatter
    class AIFormatter
      class MarkdownBuilder
        # The summary header: global percentages and generation metadata. Status is PASSED only
        # when every criterion SimpleCov measured (lines, branches, methods) is perfect, so a
        # report cannot claim PASSED while listing deficits of any kind.
        class Header
          extend T::Sig

          # Text representation for a passed coverage check
          STATUS_PASSED = 'PASSED'
          # Text representation for a failed coverage check
          STATUS_FAILED = 'FAILED'
          # Template for the report header; the method line is empty unless SimpleCov measured
          # method coverage, keeping the header byte-identical for every other run.
          TEMPLATE = "# AI Coverage Digest\n" \
                     "**Status:** %<status>s\n" \
                     "**Global Line Coverage:** %<line>s\n" \
                     "**Global Branch Coverage:** %<branch>s\n" \
                     '%<method_line>s' \
                     "**Generated At:** %<time>s (Local Timezone)\n"
          # Header line for SimpleCov >= 1.0 method coverage (`enable_coverage :method`)
          METHOD_COVERAGE_LINE = "**Global Method Coverage:** %<figure>s\n"

          # @param coverage_metrics [SimpleCov::Result] The result the figures are read from.
          sig { params(coverage_metrics: SimpleCov::Result).void }
          def initialize(coverage_metrics)
            @coverage_metrics = coverage_metrics
          end

          # @return [String] The header, ending in a newline.
          sig { returns(String) }
          def render
            line = line_figure
            branch = branch_figure
            method = method_figure
            format(TEMPLATE,
                   status: [line, branch, method].all?(&:passing?) ? STATUS_PASSED : STATUS_FAILED,
                   line: line.label || Figure::LINE_DISABLED_LABEL,
                   branch: branch.label || Figure::BRANCH_DISABLED_LABEL,
                   method_line: method.line(METHOD_COVERAGE_LINE),
                   time: Time.now.iso8601)
          end

          private

          sig { returns(Figure) }
          def line_figure
            Figure.read { @coverage_metrics.covered_percent }
          end

          # Nil when branch coverage was not enabled for the run, so the header can report "N/A"
          # rather than a misleading 100%.
          sig { returns(Figure) }
          def branch_figure
            Figure.read { Figure.ratio(@coverage_metrics.covered_branches, @coverage_metrics.total_branches) }
          end

          # Nil unless SimpleCov (>= 1.0, `enable_coverage :method`) measured methods in this run.
          sig { returns(Figure) }
          def method_figure
            Figure.read do
              if MethodDeficit.measured?(@coverage_metrics)
                Figure.ratio(@coverage_metrics.covered_methods, @coverage_metrics.total_methods)
              end
            end
          end
        end
      end
    end
  end
end
