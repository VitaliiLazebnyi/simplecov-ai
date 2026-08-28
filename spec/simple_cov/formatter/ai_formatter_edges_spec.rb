# typed: false
# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

# Edge cases of the whole pipeline; part of every subject's selection under mutant (see
# spec/support/mutant_scopes.rb).
RSpec.describe SimpleCov::Formatter::AIFormatter, mutant_expression: MutantScopes.all do
  let(:tmpdir) { Dir.mktmpdir('scai') }
  let(:report_path) { File.join(tmpdir, 'report.md') }

  before do
    described_class.reset_configuration!
    described_class.configure { |config| config.report_path = report_path }
    allow(SimpleCov).to receive(:root).and_return(tmpdir)
  end

  after do
    described_class.reset_configuration!
    FileUtils.remove_entry(tmpdir)
  end

  def resolve(code)
    described_class::ASTResolver.resolve(write_source(tmpdir, 'sample.rb', code))
  end

  def report_for(result)
    capture_stdout { described_class.new.format(result) }
    File.read(report_path)
  end

  describe 'ASTResolver edge cases' do
    it 'attributes a singleton method to its explicit foreign receiver' do
      nodes = resolve("class Patcher\n  def String.shout\n    upcase\n  end\nend\n")
      expect(nodes.map(&:name)).to eq(['main', 'Patcher', 'String.shout'])
    end

    it 'attributes a singleton method on a non-constant receiver to the enclosing context' do
      nodes = resolve("class Holder\n  obj = Object.new\n  def obj.assist\n  end\nend\n")
      expect(nodes.map(&:name)).to eq(['main', 'Holder', 'Holder.assist'])
    end

    it 'attributes methods in Struct.new / Data.define / Class.new blocks to the assigned constant' do
      nodes = resolve("Point = Struct.new(:x) do\n  def dist\n  end\nend\n" \
                      "Cfg = Data.define(:h) do\n  def url\n  end\nend\n" \
                      "Registry::Entry = Class.new do\n  def render\n  end\nend\n" \
                      "class Box\n  Item = Struct.new(:v) do\n    def show\n    end\n  end\nend\n")
      expect(nodes.map { |node| [node.name, node.type] }).to eq(
        [['main', 'Root Script Scope'], ['Point', 'Struct'], ['Point#dist', 'Instance Method'],
         ['Cfg', 'Data'], ['Cfg#url', 'Instance Method'], ['Registry::Entry', 'Class'],
         ['Registry::Entry#render', 'Instance Method'], ['Box', 'Class'], ['Box::Item', 'Struct'],
         ['Box::Item#show', 'Instance Method']]
      )
    end

    it 'does not treat non-class constant assignments as metaprogramming classes' do
      # A plain value, a safe-navigation block call, a receiverless call, a non-const receiver,
      # and a constant receiver with the wrong constructor must all be rejected, leaving only
      # the root scope.
      nodes = resolve("PLAIN = 42\n" \
                      "SAFE = obj&.each do\n  1\nend\n" \
                      "BARE = build do\n  2\nend\n" \
                      "MAPPED = [1].map do |i|\n  i\nend\n" \
                      "WRONG = Struct.old do\n  3\nend\n")
      expect(nodes.map(&:name)).to eq(['main'])
    end
  end

  describe 'configuration reset' do
    it 'restores defaults after reset_configuration!' do
      described_class.configure { |config| config.max_file_size_kb = 7 }
      described_class.reset_configuration!
      expect(described_class.configuration.max_file_size_kb).to eq(50)
    end
  end

  describe 'source encodings' do
    it 'renders snippets from a source with a non-UTF-8 magic comment through SimpleCov\'s loader' do
      path = File.join(tmpdir, 'kana.rb')
      File.binwrite(path, "# encoding: Shift_JIS\ndef read\n  '\x82\xa0'\nend\n".b)
      expect(report_for(result_for(path => { 'lines' => [nil, 1, 0, nil] })))
        .to match(/^  - \*\*Line Deficit:\*\* \[L3\] `'あ'`$/)
    end

    it 'renders a file whose comments carry stray non-UTF-8 bytes without raising' do
      path = File.join(tmpdir, 'latin.rb')
      File.binwrite(path, "# Latin-1 \xe9\ndef read\n  1\nend\n".b)
      result = result_for(path => { 'lines' => [nil, 1, 0, nil] })
      skip 'SimpleCov < 1.1 raises on invalid UTF-8 bytes itself (1.1 scrubs them)' unless classifiable?(result)
      expect(report_for(result)).to end_with("  - **Line Deficit:** [L3] `1`\n\n")
    end
  end

  # SimpleCov releases before 1.1 raise ArgumentError from their own line classification when a
  # source line carries invalid UTF-8 bytes (1.1 scrubs the source first), so no formatter can
  # process such a project there; the example verifies the formatter's side where SimpleCov can.
  def classifiable?(result)
    result.covered_percent
    true
  rescue ArgumentError
    false
  end
end
