# typed: false
# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'

# A resultset can carry a branch descriptor SimpleCov cannot decode (`.resultset.json` written
# by a crashed run, hand-edited, or merged from a foreign tool). SimpleCov < 1.0 decodes the
# stringified descriptors with `eval`, so such a key raises `SyntaxError` — a ScriptError that
# escapes any `rescue StandardError`; SimpleCov >= 1.0's RubyDataParser raises ArgumentError.
# Either way the error surfaces from every reader of the file's branches and, because SimpleCov
# computes the statistics of every criterion at once, from the global percentages as well. The
# report must contain the damage to that one file (SCAI-REQ-011).
RSpec.describe SimpleCov::Formatter::AIFormatter::MarkdownBuilder do
  let(:tmpdir) { Dir.mktmpdir('scai') }
  let(:config) { SimpleCov::Formatter::AIFormatter::Configuration.new }
  # Named to sort after the healthy file by path, so the ordering of undecodable files is observable.
  let(:corrupt_path) { write_source(tmpdir, 'zzz_corrupt.rb', "def broken\n  1\nend\n") }
  let(:plain_path) { write_source(tmpdir, 'aaa_plain.rb', "def plain\n  1\nend\n") }
  let(:corrupt_result) do
    result_for(corrupt_path => { 'lines' => [1, 1, nil], 'branches' => corrupt_branches },
               plain_path => { 'lines' => [0, 0, nil] })
  end

  before do
    allow(SimpleCov).to receive(:root).and_return(tmpdir)
    freeze_time
  end

  after { FileUtils.remove_entry(tmpdir) }

  # SimpleCov >= 1.0 rejects every malformed descriptor up front with RubyDataParser; the eval
  # of older releases only fails on invalid Ruby and otherwise yields whatever the text means.
  def strict_decoder
    defined?(SimpleCov::SourceFile::RubyDataParser) ? true : false
  end

  # The unparseable descriptor and its error: an `eval` SyntaxError below SimpleCov 1.0, an
  # ArgumentError from RubyDataParser from 1.0 on.
  def corrupt_branches
    { '[' => { '[' => 0 } }
  end

  def decode_error
    strict_decoder ? 'ArgumentError' : 'SyntaxError'
  end

  def digest_for(result)
    described_class.new(result, config).build
  end

  def error_block(error_class)
    "### `zzz_corrupt.rb`\n  - **ERROR:** SimpleCov could not decode this file's coverage data (#{error_class}); skipped.\n\n"
  end

  # Every figure is undecodable; the method line appears only where SimpleCov exposes method
  # totals at all (>= 1.0), since they are what raises there.
  def undecodable_header
    undecodable = 'N/A (coverage data could not be decoded)'
    expected_header('FAILED', undecodable, undecodable, method_label: method_coverage_supported? ? undecodable : nil)
  end

  def plain_deficits
    "### `aaa_plain.rb`\n- `#plain`\n  - **Line Deficit:** [L1] `def plain`\n  - **Line Deficit:** [L2] `1`\n\n"
  end

  it 'reports the decode error for that file first, keeps the other files and marks every global figure N/A' do
    expect(digest_for(corrupt_result)).to eq(
      undecodable_header + "## Coverage Deficits\n\n" + error_block(decode_error) + plain_deficits +
      "## Ignored Coverage Bypasses\n\n" + error_block(decode_error)
    )
  end

  it 'surfaces the exact decoder error the installed SimpleCov raises for the descriptor' do
    file = source_file(corrupt_path, { 'lines' => [1, 1, nil], 'branches' => corrupt_branches })
    expect { file.branches }.to raise_error(Object.const_get(decode_error))
  end

  # A descriptor that is valid Ruby but not an array: the strict decoder rejects it like any
  # other, while eval yields a branch without line numbers that fails the formatter's own
  # signature checks (a TypeError) once the file's deficits are grouped.
  it 'contains a descriptor that decodes to something other than an array' do
    result = result_for(corrupt_path => { 'lines' => [1, 1, nil], 'branches' => { '42' => { 'nil' => 0 } } })
    expected = if strict_decoder
                 undecodable_header + "## Coverage Deficits\n\n" + error_block('ArgumentError') +
                   "## Ignored Coverage Bypasses\n\n" + error_block('ArgumentError')
               else
                 expected_header('FAILED', '100.0%', '0.0%') + "## Coverage Deficits\n\n" + error_block('TypeError')
               end
    expect(digest_for(result)).to eq(expected)
  end

  context 'when a decodable file has a method deficit next to the corrupt file (SimpleCov >= 1.0)' do
    let(:healthy_result) do
      methods = { ['Object', :plain, 1, 0, 3, 3] => 0 }
      result_for(corrupt_path => { 'lines' => [1, 1, nil], 'branches' => corrupt_branches },
                 plain_path => { 'lines' => [1, 1, nil], 'methods' => methods })
    end

    it 'still lists the method deficits of the files that decode, matching the N/A method line' do
      skip 'method coverage needs SimpleCov >= 1.0' unless method_coverage_supported?
      digest = measuring_methods(healthy_result, {}) { digest_for(healthy_result) }
      expect(digest).to eq(
        undecodable_header + "## Coverage Deficits\n\n" + error_block('ArgumentError') +
        "### `aaa_plain.rb`\n- `#plain`\n  - **Method Deficit:** [L1-3] `#plain` never invoked\n\n" \
        "## Ignored Coverage Bypasses\n\n" + error_block('ArgumentError')
      )
    end
  end

  describe 'header figures' do
    let(:plain_result) { result_for(plain_path => { 'lines' => [1, 1, nil] }) }

    it 'labels a run without line coverage (a SimpleCov >= 1.0 branch- or method-only run) N/A without failing it' do
      allow(plain_result).to receive(:covered_percent).and_return(nil)
      expect(digest_for(plain_result)).to eq(expected_header('PASSED', 'N/A (line coverage not enabled)', '100.0%'))
    end

    it 'fails the status when only the branch figure is undecodable' do
      allow(plain_result).to receive(:total_branches).and_raise(SyntaxError, 'unexpected end-of-input')
      expect(digest_for(plain_result))
        .to eq(expected_header('FAILED', '100.0%', 'N/A (coverage data could not be decoded)'))
    end
  end
end
