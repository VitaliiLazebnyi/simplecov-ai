# typed: false
# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'

RSpec.describe SimpleCov::Formatter::AIFormatter do
  let(:tmpdir) { Dir.mktmpdir('scai') }
  let(:report_path) { File.join(tmpdir, 'report.md') }
  let(:config) { described_class.configuration }
  let(:calc_path) { write_source(tmpdir, 'calc.rb', calc_source) }
  let(:calc_result) { result_for(calc_path => calc_coverage) }

  before do
    described_class.reset_configuration!
    described_class.configure { |configuration| configuration.report_path = report_path }
    # Reports name files relative to SimpleCov.root; pointing the root at the temp directory
    # keeps the expected documents free of machine-specific paths.
    allow(SimpleCov).to receive(:root).and_return(tmpdir)
  end

  after do
    described_class.reset_configuration!
    FileUtils.remove_entry(tmpdir)
  end

  # One covered method with a missed ternary arm and one never-invoked method whose body
  # repeats a statement, so branch, line and occurrence rendering all show up.
  def calc_source
    <<~RUBY
      module Sample
        class Calc
          def sign(number)
            number.positive? ? :pos : :neg
          end

          def never_called
            @never = 1
            @never = 1
          end
        end
      end
    RUBY
  end

  def calc_coverage
    {
      'lines' => line_hits(12, covered: [1, 2, 3, 4, 7], missed: [8, 9]),
      'branches' => {
        branch_descriptor(calc_source, :if, 0, 4, 'number.positive? ? :pos : :neg') => {
          branch_descriptor(calc_source, :then, 1, 4, ':pos') => 1,
          branch_descriptor(calc_source, :else, 2, 4, ':neg') => 0
        }
      }
    }
  end

  def perfect_lines
    line_hits(12, covered: [1, 2, 3, 4, 7, 8, 9])
  end

  def expected_calc_digest
    <<~MARKDOWN
      # AI Coverage Digest
      **Status:** FAILED
      **Global Line Coverage:** 71.4%
      **Global Branch Coverage:** 50.0%
      **Generated At:** TIMESTAMP (Local Timezone)
      ## Coverage Deficits

      ### `calc.rb`
      - `Sample::Calc#sign`
        - **Branch Deficit:** [L4] Missing coverage for `else` branch: `:neg`
      - `Sample::Calc#never_called`
        - **Line Deficit:** [L8] `@never = 1` (Occurrence 1 of 2).
        - **Line Deficit:** [L9] `@never = 1` (Occurrence 2 of 2).

    MARKDOWN
  end

  def formatter
    described_class.new
  end

  def format_and_read(result)
    capture_stdout { formatter.format(result) }
    File.read(report_path)
  end

  def without_timestamp(digest)
    digest.sub(/\*\*Generated At:\*\* \S+/, '**Generated At:** TIMESTAMP')
  end

  describe '.configure' do
    it 'yields the process-global configuration' do
      described_class.configure { |configuration| configuration.max_file_size_kb = 10 }
      expect(config.max_file_size_kb).to eq(10)
    end

    it 'does nothing if no block is given' do
      expect { described_class.configure }.not_to raise_error
    end
  end

  describe '#format' do
    it 'writes the digest to the configured path and announces the path on STDOUT' do
      announcement = capture_stdout { formatter.format(calc_result) }
      expect([announcement, File.exist?(report_path)])
        .to eq(["AI coverage digest written to #{report_path}\n", true])
    end

    it 'renders the header, then each deficit file with its nodes and exact snippets in source order' do
      expect(without_timestamp(format_and_read(calc_result))).to eq(expected_calc_digest)
    end

    it 'stamps the generation time as an ISO 8601 local timestamp' do
      iso8601 = /\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:Z|[+-]\d{2}:\d{2})/
      timestamp_line = /^\*\*Generated At:\*\* #{iso8601} \(Local Timezone\)$/
      expect(format_and_read(calc_result)).to match(timestamp_line)
    end

    it 'keeps the sub-line branch snippet when the result was rebuilt from the JSON resultset' do
      expect(without_timestamp(format_and_read(merged_result(calc_result)))).to eq(expected_calc_digest)
    end

    it 'echoes the whole digest instead of the announcement when output_to_console is on' do
      config.output_to_console = true
      printed = capture_stdout { formatter.format(calc_result) }
      expect([printed.start_with?('# AI Coverage Digest'), printed.include?('written to')]).to eq([true, false])
    end

    it 'summarises each node with coarse granularity' do
      config.granularity = :coarse
      expect(format_and_read(calc_result)).to end_with(<<~MARKDOWN)
        - `Sample::Calc#sign`
          - **Deficit:** Contains unexecuted lines or branches.
        - `Sample::Calc#never_called`
          - **Deficit:** Contains unexecuted lines or branches.

      MARKDOWN
    end

    it 'truncates over-long snippets at the configured line budget' do
      config.max_snippet_lines = 1
      long_path = write_source(tmpdir, 'wide.rb', "def wide\n  #{'a' * 100}\nend\n")
      digest = format_and_read(result_for(long_path => { 'lines' => [1, 0, nil] }))
      expect(digest).to end_with("- `#wide`\n  - **Line Deficit:** [L2] `#{'a' * 80}...`\n\n")
    end

    context 'with a fully covered result' do
      let(:covered_result) do
        branches = calc_coverage['branches'].transform_values { |arms| arms.transform_values { 1 } }
        result_for(calc_path => { 'lines' => perfect_lines, 'branches' => branches })
      end

      it 'reports PASSED and nothing but the header' do
        expect(format_and_read(covered_result))
          .to match(/\A# AI Coverage Digest\n\*\*Status:\*\* PASSED\n.*\n.*\n.*\n\z/)
      end
    end

    context 'when branch coverage is not enabled for the run' do
      before { allow(SimpleCov).to receive(:branch_coverage?).and_return(false) }

      it 'reports N/A and judges the status by line coverage alone' do
        digest = format_and_read(result_for(calc_path => { 'lines' => perfect_lines }))
        expect(digest.lines[1..3].join).to eq(
          "**Status:** PASSED\n**Global Line Coverage:** 100.0%\n" \
          "**Global Branch Coverage:** N/A (branch coverage not enabled)\n"
        )
      end
    end

    it 'reports 100.0% branch coverage when the run recorded no branches at all' do
      digest = format_and_read(result_for(calc_path => { 'lines' => perfect_lines }))
      expect(digest.lines[3]).to eq("**Global Branch Coverage:** 100.0%\n")
    end

    context 'when a deficit file is not valid Ruby' do
      let(:broken_path) { write_source(tmpdir, 'broken.rb', "class Broken\n  def half\n    1 +\n  end\n") }

      it 'degrades that file to raw line numbers under a parse-failure notice' do
        expect(format_and_read(result_for(broken_path => { 'lines' => [1, 1, 0, nil] }))).to end_with(<<~MARKDOWN)
          ### `broken.rb`
            - **ERROR:** AST Parsing Failed. Showing raw line numbers instead.
            - **Line Deficit:** [L3] `1 +`

        MARKDOWN
      end
    end

    context 'with a branch SimpleCov recorded beyond the end of the file (a file that shrank)' do
      let(:stale_result) do
        stale_arm = { multiline_branch_descriptor(:then, 1, 99, 100) => 0 }
        branches = { multiline_branch_descriptor(:if, 0, 99, 100) => stale_arm }
        result_for(calc_path => { 'lines' => calc_coverage['lines'], 'branches' => branches })
      end

      it 'labels the deficit by its line range instead of a node' do
        expect(format_and_read(stale_result)).to end_with(<<~MARKDOWN)
          - `Lines 99-100`
            - **Branch Deficit:** [L99-100] Missing coverage for `then` branch: ``

        MARKDOWN
      end
    end

    context 'when the source cannot be read while snippets are rendered' do
      before do
        unreadable = calc_result.files.first
        [unreadable.missed_lines, unreadable.missed_branches, unreadable.skipped_lines]
        allow(unreadable).to receive(:src).and_raise(Errno::EACCES)
      end

      it 'lists the deficits without snippets rather than raising' do
        expect(format_and_read(calc_result)).to end_with(<<~MARKDOWN)
          - `Sample::Calc#sign`
            - **Branch Deficit:** [L4] Missing coverage for `else` branch: ``
          - `Sample::Calc#never_called`
            - **Line Deficit:** [L8] ``
            - **Line Deficit:** [L9] ``

        MARKDOWN
      end
    end

    context 'with a bypassed method' do
      let(:legacy_path) { write_source(tmpdir, 'legacy.rb', legacy_source) }
      let(:legacy_result) do
        result_for(legacy_path => { 'lines' => line_hits(11, covered: [1, 8], missed: [3, 4, 9]) })
      end

      def legacy_source
        <<~RUBY
          class Legacy
            #{nocov_marker}
            def obsolete
              raise NotImplementedError
            end
            #{nocov_marker}

            def live
              :live
            end
          end
        RUBY
      end

      it 'reports the deficit outside the region and the bypass with its directive text' do
        expect(format_and_read(legacy_result)).to end_with(<<~MARKDOWN)
          ## Coverage Deficits

          ### `legacy.rb`
          - `Legacy#live`
            - **Line Deficit:** [L9] `:live`

          ## Ignored Coverage Bypasses

          ### `legacy.rb`
          - `Legacy#obsolete`
            - **Bypass Present:** Coverage explicitly ignored via `#{nocov_marker}`.

        MARKDOWN
      end

      it 'omits the bypass section when bypass auditing is disabled' do
        config.include_bypasses = false
        expect(format_and_read(legacy_result)).not_to match(/Ignored Coverage Bypasses|Legacy#obsolete/)
      end

      it 'resolves the AST of a file once for both its deficits and its bypasses' do
        allow(described_class::ASTResolver).to receive(:resolve).and_call_original
        capture_stdout { formatter.format(legacy_result) }
        expect(described_class::ASTResolver).to have_received(:resolve).with(legacy_path).once
      end
    end
  end

  describe 'report destination' do
    it 'writes to ai_report.md inside SimpleCov.coverage_path when no report_path is configured' do
      described_class.reset_configuration!
      coverage_dir = File.join(tmpdir, 'custom_cov')
      allow(SimpleCov).to receive(:coverage_path).and_return(coverage_dir)
      capture_stdout { formatter.format(calc_result) }
      expect(File.exist?(File.join(coverage_dir, 'ai_report.md'))).to be(true)
    end

    it 'resolves a relative report_path against SimpleCov.root' do
      config.report_path = 'reports/digest.md'
      capture_stdout { formatter.format(calc_result) }
      expect(File.exist?(File.join(tmpdir, 'reports', 'digest.md'))).to be(true)
    end

    it 'uses an absolute report_path unchanged' do
      absolute = File.join(tmpdir, 'nested', 'abs_report.md')
      config.report_path = absolute
      capture_stdout { formatter.format(calc_result) }
      expect(File.exist?(absolute)).to be(true)
    end
  end

  describe 'bypass auditing of a file whose AST cannot be resolved' do
    it 'reports the raw deficits and no bypass for the skipped region' do
      source = "class Broken\n#{nocov_marker}\ndef skipped\nend\n#{nocov_marker}\ndef half\n  1 +\nend\n"
      broken_path = write_source(tmpdir, 'broken.rb', source)
      coverage = { 'lines' => [1, nil, 1, nil, nil, 1, 0, nil] }
      capture_stdout { formatter.format(result_for(broken_path => coverage)) }
      expect(File.read(report_path)).to end_with("  - **Line Deficit:** [L7] `1 +`\n\n")
    end
  end
end
