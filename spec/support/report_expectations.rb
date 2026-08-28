# typed: false
# frozen_string_literal: true

# Shared by the specs that compare whole reports: the instant every report is generated at
# (SCAI-REQ-008: time is mocked), in a fixed offset so the header's local-timezone label is the
# same on every machine, and the header a run at that instant produces.
module ReportExpectations
  FROZEN_TIME = Time.new(2026, 4, 21, 23, 40, 44, '+09:00').freeze
  # {FROZEN_TIME} as the header prints it.
  FROZEN_ISO8601 = '2026-04-21T23:40:44+09:00'

  # Pins `Time.now` to {FROZEN_TIME} for the example.
  def freeze_time
    allow(Time).to receive(:now).and_return(FROZEN_TIME)
  end

  # The report header of a run at {FROZEN_TIME}, with the method line only when given.
  def expected_header(status, line_label, branch_label, method_label: nil)
    method_line = method_label ? "**Global Method Coverage:** #{method_label}\n" : ''
    "# AI Coverage Digest\n**Status:** #{status}\n**Global Line Coverage:** #{line_label}\n" \
      "**Global Branch Coverage:** #{branch_label}\n#{method_line}" \
      "**Generated At:** #{FROZEN_ISO8601} (Local Timezone)\n"
  end
end
