# typed: false
# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

# Directive strings appear inline within single source lines (e.g. inside "..." literals), so
# the repository directive auditor — which only matches directives at the start of a line — is
# not triggered and no placeholder evasion is required.
RSpec.describe SimpleCov::Formatter::AIFormatter do
  let(:tmpdir) { Dir.mktmpdir }

  let(:empty_result) do
    instance_double(SimpleCov::Result, covered_percent: 100.0, covered_branches: 1, total_branches: 1, files: [])
  end

  let(:bare_result) { instance_double(SimpleCov::Result, covered_percent: 100.0, files: []) }

  let(:legacy_result) do
    branch = instance_double(SimpleCov::SourceFile::Branch, start_line: 3, end_line: 3, type: :else)
    file = source_double('lib/legacy.rb', missed_lines: [], missed_branches: [branch], branches: [branch])
    stub_covered_percent(file, line: 100.0)
    allow(file).to receive(:respond_to?).with(:branches).and_return(true)
    allow(file).to receive(:respond_to?).with(:branches_coverage_percent).and_return(true)
    allow(file).to receive(:branches_coverage_percent).and_return(50.0)
    allow(File).to receive(:readlines).with('lib/legacy.rb').and_return((1..5).map { |num| "line #{num}\n" })
    result_with(file, covered_branches: 1, total_branches: 2)
  end

  let(:indeterminate_branch_result) do
    file = source_double('lib/legacy2.rb', missed_lines: [], missed_branches: [])
    stub_covered_percent(file, line: 100.0)
    allow(file).to receive(:respond_to?).with(:branches_coverage_percent).and_return(false)
    result_with(file)
  end

  let(:unreadable_result) do
    missed = instance_double(SimpleCov::SourceFile::Line, line_number: 2)
    file = source_double('lib/unreadable.rb', missed_lines: [missed], missed_branches: [])
    stub_covered_percent(file, line: 40.0)
    allow(file).to receive(:respond_to?).with(:branches).and_return(false)
    allow(file).to receive(:respond_to?).with(:branches_coverage_percent).and_return(false)
    allow(described_class::ASTResolver).to receive(:resolve).and_return([])
    result_with(file, covered_percent: 40.0)
  end

  before { described_class.reset_configuration! }

  after do
    described_class.reset_configuration!
    FileUtils.remove_entry(tmpdir) if File.directory?(tmpdir)
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
      # and a constant receiver with the wrong constructor must all be rejected.
      nodes = resolve("PLAIN = 42\n" \
                      "SAFE = obj&.each do\n  1\nend\n" \
                      "BARE = build do\n  2\nend\n" \
                      "MAPPED = [1].map do |i|\n  i\nend\n" \
                      "WRONG = Struct.old do\n  3\nend\n")
      expect(nodes).to be_empty
    end

    it 'bypasses a method wrapping a nocov region without touching its sibling' do
      nodes = resolve("def wrapper\n  a = 1\n  # :nocov:\n  b = 2\n  # :nocov:\nend\n\ndef sibling\n  0\nend\n")
      bypassed = nodes.find { |node| node.name == '#wrapper' }.bypass_reasons.any?
      sibling_clean = nodes.find { |node| node.name == '#sibling' }.bypass_reasons.empty?
      expect([bypassed, sibling_clean]).to eq([true, true])
    end

    it 'ignores a bypass region that wraps only top-level code with no enclosing node' do
      nodes = resolve("# :nocov:\nTOP = 1\n# :nocov:\ndef later\nend\n")
      later = nodes.find { |candidate| candidate.name == '#later' }
      expect([nodes.size, later.bypass_reasons]).to eq([1, []])
    end
  end

  describe 'configuration reset' do
    it 'restores defaults after reset_configuration!' do
      described_class.configure { |config| config.max_file_size_kb = 7 }
      described_class.reset_configuration!
      expect(described_class.configuration.max_file_size_kb).to eq(50)
    end
  end

  describe 'report path resolution' do
    it 'writes to an absolute report path unchanged' do
      absolute = File.join(tmpdir, 'nested', 'abs_report.md')
      described_class.configure { |config| config.report_path = absolute }
      described_class.new.format(empty_result)
      expect(File.exist?(absolute)).to be(true)
    end
  end

  describe 'header branch coverage reporting' do
    it 'reports N/A when the result does not expose branch metrics at all' do
      allow(bare_result).to receive(:respond_to?).and_return(false)
      expect(report_for(bare_result)).to include('**Global Branch Coverage:** N/A (branch coverage not enabled)')
    end
  end

  describe 'branch coverage percent fallback for simplecov < 1.0' do
    it 'falls back to branches_coverage_percent when covered_percent rejects a criterion' do
      expect(report_for(legacy_result)).to include('**Branch Deficit:**')
    end

    it 'treats branch coverage as complete when neither criterion API is available' do
      expect(report_for(indeterminate_branch_result)).to include('**Status:** PASSED')
    end

    it 'degrades to no snippets when a deficit file cannot be read' do
      allow(File).to receive(:readlines).with('lib/unreadable.rb').and_raise(Errno::ENOENT)
      expect(report_for(unreadable_result)).to include('lib/unreadable.rb')
    end
  end

  def resolve(code)
    path = File.join(tmpdir, 'sample.rb')
    File.write(path, code)
    described_class::ASTResolver.resolve(path)
  end

  def report_for(result)
    described_class.configure { |config| config.report_path = File.join(tmpdir, 'r.md') }
    described_class.new.format(result)
    File.read(described_class.configuration.report_path)
  end

  def source_double(filename, **stubs)
    file = instance_double(SimpleCov::SourceFile, filename: filename, project_filename: filename, **stubs)
    allow(file).to receive(:respond_to?).with(:coverage_data).and_return(false)
    file
  end

  # Stubs covered_percent to return the line percentage for the no-argument call and to raise
  # ArgumentError for a criterion argument. This mirrors simplecov < 1.0 (whose covered_percent
  # takes no criterion) and, because verify_partial_doubles enforces the installed method's
  # arity on the call itself, is the only cross-version-safe shape; branch percentages are
  # therefore supplied to mocks via branches_coverage_percent (the criterion-less fallback).
  def stub_covered_percent(file, line:)
    allow(file).to receive(:covered_percent) do |*args|
      raise ArgumentError unless args.empty?

      line
    end
  end

  def result_with(file, **overrides)
    defaults = { covered_percent: 100.0, covered_branches: 0, total_branches: 0, files: [file] }
    instance_double(SimpleCov::Result, **defaults, **overrides)
  end
end
