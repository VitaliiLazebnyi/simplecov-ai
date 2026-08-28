# typed: false
# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe SimpleCov::Formatter::AIFormatter do
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
      expect(nodes.map(&:name)).to include('String.shout')
    end

    it 'attributes a singleton method on a non-constant receiver to the enclosing context' do
      nodes = resolve("class Holder\n  obj = Object.new\n  def obj.assist\n  end\nend\n")
      expect(nodes.map(&:name)).to include('Holder.assist')
    end

    it 'attributes methods in Struct.new / Data.define / Class.new blocks to the assigned constant' do
      nodes = resolve("Point = Struct.new(:x) do\n  def dist\n  end\nend\n" \
                      "Cfg = Data.define(:h) do\n  def url\n  end\nend\n" \
                      "Registry::Entry = Class.new do\n  def render\n  end\nend\n" \
                      "class Box\n  Item = Struct.new(:v) do\n    def show\n    end\n  end\nend\n")
      expect(nodes.map(&:name)).to include('Point#dist', 'Cfg#url', 'Registry::Entry#render', 'Box::Item#show')
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

  describe 'branch coverage percent fallback for simplecov < 1.0' do
    let(:source) { "def pick(flag)\n  flag ? :a : :b\nend\n" }
    let(:path) { write_source(tmpdir, 'pick.rb', source) }
    let(:legacy_result) do
      branches = { branch_descriptor(source, :if, 0, 2, 'flag ? :a : :b') => {
        branch_descriptor(source, :then, 1, 2, ':a') => 1, branch_descriptor(source, :else, 2, 2, ':b') => 0
      } }
      result_for(path => { 'lines' => [1, 1, nil], 'branches' => branches })
    end

    before do
      # simplecov < 1.0's SourceFile#covered_percent takes no criterion and raises ArgumentError
      # when given one, and its branches_coverage_percent computes the figure itself; on newer
      # releases (where the latter delegates to covered_percent) that shape is reproduced on the
      # real object.
      legacy_file = legacy_result.files.first
      allow(legacy_file).to receive(:covered_percent) { |*criterion| criterion.empty? ? 100.0 : raise(ArgumentError) }
      allow(legacy_file).to receive(:branches_coverage_percent).and_return(50.0)
    end

    it 'falls back to branches_coverage_percent so the branch deficit is still reported' do
      expect(report_for(legacy_result))
        .to end_with("  - **Branch Deficit:** [L2] Missing coverage for `else` branch: `:b`\n\n")
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
      File.binwrite(path, "# caf\xe9\ndef read\n  1\nend\n".b)
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
