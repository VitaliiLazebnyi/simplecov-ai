# typed: strict
# frozen_string_literal: true

module SimpleCov
  module Formatter
    class AIFormatter
      class MarkdownBuilder
        # Enforces the configured size ceiling on the report. Every section appends through
        # {#admit}, which only writes a fragment when it still fits below the ceiling minus the
        # room reserved for the closing truncation notice, so the finished file never exceeds
        # `max_file_size_kb`. Fragments are admitted whole: one that does not fit is dropped and
        # reported back to the caller, which then closes its section. The notice itself is
        # written through {#write_notice} once every section has reported what it left out.
        class ReportBudget
          extend T::Sig

          # The number of bytes in a kilobyte (metric kB, matching the "kB" unit shown to users)
          BYTES_PER_KB = T.let(1000, Integer)
          # Alert heading for truncated reports
          TRUNCATION_ALERT_HEADING = T.let("> **[WARNING] TRUNCATION NOTIFICATION:**\n", String)
          # Alert body for truncated reports, naming what the size budget left out
          TRUNCATION_ALERT_BODY = T.let(
            '> The report reached the maximum token constraint (%<limit>d kB) and was truncated: ' \
            '%<deficit_files>d deficit file(s) and %<bypass_files>d bypass file(s) omitted or cut short. ' \
            'Lowest-coverage files are listed first; resolve the deficits above to reveal the remaining ' \
            "ones in subsequent test runs.\n",
            String
          )
          # Bytes kept free, beyond the notice itself, for the blank-line separators the
          # sections write outside the admission check.
          SEPARATOR_MARGIN = T.let(4, Integer)

          # @param buffer [StringIO] The report being composed.
          # @param limit_kb [Integer] The configured ceiling for the whole file, in kB.
          # @param file_count [Integer] The number of files in the result — the most any notice
          #   could name, so the reserve is sized for the widest possible notice up front.
          sig { params(buffer: StringIO, limit_kb: Integer, file_count: Integer).void }
          def initialize(buffer, limit_kb, file_count)
            @buffer = buffer
            @limit_kb = limit_kb
            reserved_bytes = notice(file_count, file_count).bytesize + SEPARATOR_MARGIN
            @admissible_bytes = T.let((limit_kb * BYTES_PER_KB) - reserved_bytes, Integer)
          end

          # Appends the fragment when the report stays within the admissible size.
          #
          # @param fragment [String] The Markdown fragment to append.
          # @return [Boolean] Whether the fragment was written.
          sig { params(fragment: String).returns(T::Boolean) }
          def admit(fragment)
            fits = @buffer.string.bytesize + fragment.bytesize <= @admissible_bytes
            @buffer.write(fragment) if fits
            fits
          end

          # Appends a fragment regardless of the budget: the header and the paragraph separators
          # (which the reserve accounts for) are always present.
          #
          # @param fragment [String] The Markdown fragment to append.
          # @return [void]
          sig { params(fragment: String).void }
          def write(fragment)
            @buffer.write(fragment)
          end

          # Appends the truncation notice naming what the budget left out.
          #
          # @param omitted_deficit_files [Integer] Deficit files omitted or cut short.
          # @param omitted_bypass_files [Integer] Bypass files omitted or cut short.
          # @return [void]
          sig { params(omitted_deficit_files: Integer, omitted_bypass_files: Integer).void }
          def write_notice(omitted_deficit_files, omitted_bypass_files)
            @buffer.write(notice(omitted_deficit_files, omitted_bypass_files))
          end

          private

          sig { params(deficit_files: Integer, bypass_files: Integer).returns(String) }
          def notice(deficit_files, bypass_files)
            TRUNCATION_ALERT_HEADING +
              format(TRUNCATION_ALERT_BODY, limit: @limit_kb, deficit_files: deficit_files, bypass_files: bypass_files)
          end
        end
      end
    end
  end
end
