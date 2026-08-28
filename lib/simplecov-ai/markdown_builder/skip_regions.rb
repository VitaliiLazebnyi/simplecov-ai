# typed: strict
# frozen_string_literal: true

module SimpleCov
  module Formatter
    class AIFormatter
      class MarkdownBuilder
        # Derives coverage-bypass regions from SimpleCov's own verdicts instead of re-parsing
        # directives: the lines SimpleCov marked skipped (`# :nocov:` pairs, `# simplecov:disable`
        # blocks and trailing comments, a custom nocov token) form contiguous regions, and the
        # branches it skipped outside those regions (a `# simplecov:disable branch` scope) add
        # their own. Each region is paired with the directive comment that caused it — found on
        # the region's first line or the nearest line above — so the report quotes the exact
        # text a maintainer wrote. Whatever SimpleCov did not skip (a directive inside a heredoc,
        # a `simplecov:disable` on a SimpleCov that predates it) is not a bypass here either.
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
            file.skipped_lines.any? || branches_of(file).any?(&:skipped?)
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
            line_ranges = contiguous_ranges(file.skipped_lines.map(&:line_number))
            branch_ranges = skipped_branch_ranges(file).reject do |branch_range|
              line_ranges.any? { |line_range| LineSpan.encloses?(line_range, branch_range) }
            end
            pattern = directive_pattern
            (line_ranges + branch_ranges).sort_by(&:begin)
                                         .map { |range| [range, reason_for(range, source_lines, pattern)] }
          end

          # `SourceFile#branches` arrived with branch coverage in SimpleCov 0.18 and is empty
          # when branch coverage is off; the guard keeps foreign result objects safe.
          sig { params(file: SimpleCov::SourceFile).returns(T::Array[SimpleCov::SourceFile::Branch]) }
          def self.branches_of(file)
            (file.respond_to?(:branches) && file.branches) || []
          end

          sig { params(file: SimpleCov::SourceFile).returns(T::Array[T::Range[Integer]]) }
          def self.skipped_branch_ranges(file)
            branches_of(file).select(&:skipped?).map { |branch| branch.start_line..branch.end_line }.uniq
          end

          sig { params(line_numbers: T::Array[Integer]).returns(T::Array[T::Range[Integer]]) }
          def self.contiguous_ranges(line_numbers)
            line_numbers.sort.each_with_object(T.let([], T::Array[T::Range[Integer]])) do |line_number, ranges|
              open_range = ranges.last
              if open_range && open_range.end + 1 == line_number
                ranges[-1] = (open_range.begin..line_number)
              else
                ranges << (line_number..line_number)
              end
            end
          end

          # Walks upward from the region's first line to the nearest directive comment: a line
          # region always starts on its directive (SimpleCov's skipped ranges include the marker
          # lines), while a branch-only region starts on the arm and finds its
          # `# simplecov:disable branch` on the lines above.
          sig do
            params(range: T::Range[Integer], source_lines: T::Array[String], pattern: Regexp).returns(String)
          end
          def self.reason_for(range, source_lines, pattern)
            range.begin.downto(1) do |line_number|
              comment = source_lines.fetch(line_number - 1, '')[pattern]
              return comment.strip if comment
            end
            FALLBACK_REASON
          end

          # Matches a `# simplecov:disable …` comment or a nocov marker carrying the token
          # SimpleCov is configured with, from its `#` to the end of the line.
          sig { returns(Regexp) }
          def self.directive_pattern
            /#\s*(?:simplecov\s*:\s*disable\b|:#{Regexp.escape(nocov_token)}:).*/
          end

          sig { returns(String) }
          def self.nocov_token
            reader = T.must(NOCOV_TOKEN_READERS.find { |candidate| SimpleCov.respond_to?(candidate) })
            T.cast(SimpleCov.public_send(reader), String)
          end

          private_class_method :branches_of, :skipped_branch_ranges, :contiguous_ranges, :reason_for,
                               :directive_pattern, :nocov_token
        end
      end
    end
  end
end
