# typed: false
# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'

# Fuzzes `#format` with coverage data in the shapes a damaged resultset can take (see
# spec/support/coverage_fuzzer.rb): whatever SimpleCov raises while decoding a file's data must
# be contained to that file (SCAI-REQ-011), so the formatter never raises and always writes a
# report. Failures name the seed; FORMATTER_FUZZ_SEED replays or shifts the sequence.
RSpec.describe SimpleCov::Formatter::AIFormatter do
  let(:tmpdir) { Dir.mktmpdir('scai-fuzz') }
  let(:report_path) { File.join(tmpdir, 'report.md') }
  let(:base_seed) { Integer(ENV.fetch('FORMATTER_FUZZ_SEED', CoverageFuzzer::DEFAULT_SEED)) }
  # A parsable file with a branch, an unparsable one and one with a nocov region, so deficit
  # rendering, the raw fallback and bypass auditing all run over the fuzzed data.
  let(:paths) do
    [write_source(tmpdir, 'plain.rb', "def plain(flag)\n  flag ? 1 : 2\nend\n"),
     write_source(tmpdir, 'broken.rb', "class Broken\n  def half\n    1 +\n  end\n"),
     write_source(tmpdir, 'skipped.rb', "#{nocov_marker}\nLIMIT = 1\n#{nocov_marker}\ndef kept\n  LIMIT\nend\n")]
  end

  before do
    described_class.reset_configuration!
    described_class.configure { |configuration| configuration.report_path = report_path }
    allow(SimpleCov).to receive(:root).and_return(tmpdir)
  end

  after do
    described_class.reset_configuration!
    FileUtils.remove_entry(tmpdir)
  end

  # SimpleCov's own constructor may reject a shape outright; that leaves nothing for the
  # formatter to contain, so such a case is skipped.
  def build_result(coverage_by_path)
    result_for(coverage_by_path)
  rescue StandardError, ScriptError
    nil
  end

  # @return [String, nil] The failure for `seed`, or nil when the report was written.
  def failure_for(seed)
    fuzzer = CoverageFuzzer.new(seed)
    coverage_by_path = paths.first(1 + (seed % 3)).to_h { |path| [path, fuzzer.coverage] }
    result = build_result(coverage_by_path)
    return nil unless result

    File.delete(report_path) if File.exist?(report_path)
    capture_stdout { described_class.new.format(result) }
    File.exist?(report_path) ? nil : "seed #{seed}: no report written for #{coverage_by_path}"
  rescue StandardError, ScriptError => error
    "seed #{seed}: #{error.class}: #{error.message}\n  #{coverage_by_path}\n  #{error.backtrace.first(6).join("\n  ")}"
  end

  it "never raises and always writes a report for #{CoverageFuzzer::CASE_COUNT} fuzzed resultsets" do
    failures = (0...CoverageFuzzer::CASE_COUNT).filter_map { |offset| failure_for(base_seed + offset) }
    expect(failures).to be_empty,
                        "#{failures.size} of #{CoverageFuzzer::CASE_COUNT} cases failed; first:\n#{failures.first}"
  end
end
