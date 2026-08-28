# typed: strict
# frozen_string_literal: true

module SimpleCov
  module Formatter
    class AIFormatter
      class MarkdownBuilder
        # Derives coverage-bypass regions from SimpleCov's own verdicts instead of re-parsing
        # directives: the lines SimpleCov marked skipped (`:nocov:` pairs, `simplecov:disable`
        # blocks and trailing comments, a custom nocov token) form contiguous regions, and the
        # branches it skipped outside those regions (a `simplecov:disable branch` scope) add
        # their own. Each region is paired with the directive comment that caused it — found on
        # the region's first line or the nearest line above — so the report quotes the exact
        # text a maintainer wrote. Whatever SimpleCov did not skip (a directive inside a heredoc,
        # a `simplecov:disable` on a SimpleCov that predates it) is not a bypass here either, and
        # neither is a skipped region made only of comments and blank lines, which takes nothing
        # out of any figure. (SimpleCov honours a directive wherever it appears in a comment, so
        # the directives are spelled without their leading `#` throughout this file.)
        module SkipRegions
          extend T::Sig

          # Reason reported when the directive that produced a region cannot be located.
          FALLBACK_REASON = T.let('coverage skipped by SimpleCov', String)
          # Readers of the configured nocov token, newest SimpleCov first: the public
          # `nocov_token` reader warns about its own deprecation on SimpleCov >= 1.0.
          NOCOV_TOKEN_READERS = T.let(%i[current_nocov_token nocov_token].freeze, T::Array[Symbol])

          # Cheap pre-check (no AST parse) for whether SimpleCov skipped anything in the file.
          #
          # @param file [SimpleCov::SourceFile] The file to inspect.
          # @return [Boolean] Whether any line or branch was skipped.
          sig { params(file: SimpleCov::SourceFile).returns(T::Boolean) }
          def self.any?(file)
            file.skipped_lines.any? || file.branches.any?(&:skipped?)
          end

          # @param file [SimpleCov::SourceFile] The file to inspect.
          # @param source_lines [Array<String>] The file's source, searched for the directives.
          # @return [Array<Array(Range<Integer>, String)>] Skipped line ranges with the reason
          #   text, in source order.
          sig do
            params(file: SimpleCov::SourceFile, source_lines: T::Array[String])
              .returns(T::Array[ASTResolver::BypassScanner::Region])
          end
          def self.of(file, source_lines)
            line_ranges = skipped_line_ranges(file)
            branch_ranges = skipped_branch_ranges(file).reject do |branch_range|
              line_ranges.any? { |line_range| LineSpan.encloses?(line_range, branch_range) }
            end
            pattern = directive_pattern
            (line_ranges + branch_ranges).sort_by(&:begin)
                                         .map { |range| [range, reason_for(range, source_lines, pattern)] }
          end

          # `SourceFile#branches` (SimpleCov >= 0.18) is empty when branch coverage is off.
          sig { params(file: SimpleCov::SourceFile).returns(T::Array[T::Range[Integer]]) }
          def self.skipped_branch_ranges(file)
            file.branches.select(&:skipped?).map { |branch| branch.start_line..branch.end_line }.uniq
          end

          # A region holding nothing SimpleCov would count — comments and blank lines only, such as
          # a doc comment that mentions a directive — excludes nothing from any figure and is
          # dropped; a region with at least one relevant line is a bypass, whatever else it wraps.
          sig { params(file: SimpleCov::SourceFile).returns(T::Array[T::Range[Integer]]) }
          def self.skipped_line_ranges(file)
            contiguous_runs(file.skipped_lines).select { |run| run.any? { |line| relevant?(line) } }
                                               .map { |run| run.fetch(0).line_number..run.fetch(-1).line_number }
          end

          # SimpleCov lists skipped lines in line order, so a run closes at the first gap.
          sig do
            params(lines: T::Array[SimpleCov::SourceFile::Line]).returns(T::Array[T::Array[SimpleCov::SourceFile::Line]])
          end
          def self.contiguous_runs(lines)
            lines.each_with_object(T.let([], T::Array[T::Array[SimpleCov::SourceFile::Line]])) do |line, runs|
              open_run = runs.last
              if open_run && open_run.fetch(-1).line_number + 1 == line.line_number
                open_run << line
              else
                runs << [line]
              end
            end
          end

          # Whether SimpleCov's own classifier (`SimpleCov::LinesClassifier`) counts the line:
          # comments and blank lines are never relevant, and a skipped line keeps that verdict
          # whether the file was loaded (Ruby's coverage leaves them nil) or only tracked
          # (SimpleCov classifies its text).
          sig { params(line: SimpleCov::SourceFile::Line).returns(T::Boolean) }
          def self.relevant?(line)
            !LinesClassifier.whitespace_line?(line.src)
          end

          # Walks upward from the region's first line to the nearest directive comment: a line
          # region always starts on its directive (SimpleCov's skipped ranges include the marker
          # lines), while a branch-only region starts on the arm and finds its
          # `simplecov:disable branch` on the lines above.
          sig do
            params(range: T::Range[Integer], source_lines: T::Array[String], pattern: Regexp).returns(String)
          end
          def self.reason_for(range, source_lines, pattern)
            range.begin.downto(1) do |line_number|
              comment = source_lines.fetch(line_number - 1, '')[pattern]
              return comment.rstrip if comment
            end
            FALLBACK_REASON
          end

          # Matches a `simplecov:disable …` comment or a nocov marker carrying the token
          # SimpleCov is configured with, from its `#` to the end of the line.
          sig { returns(Regexp) }
          def self.directive_pattern
            /#\s*(?:simplecov\s*:\s*disable\b|:#{Regexp.escape(nocov_token)}:).*/
          end

          sig { returns(String) }
          def self.nocov_token
            reader = NOCOV_TOKEN_READERS.find { |candidate| SimpleCov.respond_to?(candidate) }
            T.cast(SimpleCov.public_send(T.must(reader)), String)
          end

          private_class_method :skipped_branch_ranges, :skipped_line_ranges, :contiguous_runs, :relevant?, :reason_for,
                               :directive_pattern, :nocov_token
        end
      end
    end
  end
end
