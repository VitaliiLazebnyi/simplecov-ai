# typed: false
# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'

RSpec.describe SimpleCov::Formatter::AIFormatter::MarkdownBuilder::BranchEnricher do
  let(:tmpdir) { Dir.mktmpdir('scai') }
  let(:source) { "def sign(number)\n  number.positive? ? :pos : :neg\nend\n" }
  let(:path) { write_source(tmpdir, 'sign.rb', source) }
  let(:condition) { branch_descriptor(source, :if, 0, 2, 'number.positive? ? :pos : :neg') }
  let(:then_arm) { branch_descriptor(source, :then, 1, 2, ':pos') }
  let(:else_arm) { branch_descriptor(source, :else, 2, 2, ':neg') }
  let(:live_coverage) { { 'lines' => [1, 1, nil], 'branches' => { condition => { then_arm => 1, else_arm => 0 } } } }

  after { FileUtils.remove_entry(tmpdir) }

  # The shape a result has after SimpleCov rebuilt it from .resultset.json; the branches are
  # built by SimpleCov (with its own decoder) before the example tampers with the decoders.
  def stringified_file
    arms = { then_arm.to_s => 1, else_arm.to_s => 0 }
    file = source_file(path, { 'lines' => [1, 1, nil], 'branches' => { condition.to_s => arms } })
    file.branches
    file
  end

  def columns_by_type(file)
    described_class.enrich(file).to_h { |branch, columns| [branch.type, columns] }
  end

  # The real RubyDataParser (SimpleCov >= 1.0) as a spy, or a stand-in on older releases.
  def ruby_data_parser_spy(file)
    if defined?(SimpleCov::SourceFile::RubyDataParser)
      allow(SimpleCov::SourceFile::RubyDataParser).to receive(:call).and_call_original
      SimpleCov::SourceFile::RubyDataParser
    else
      parser = stub_const('SimpleCov::SourceFile::RubyDataParser', Module.new { def self.call(_descriptor); end })
      allow(parser).to receive(:call) { |descriptor| file.send(:restore_ruby_data_structure, descriptor) }
      parser
    end
  end

  def without_any_decoder(file)
    hide_const('SimpleCov::SourceFile::RubyDataParser')
    if file.respond_to?(:restore_ruby_data_structure, true)
      file.singleton_class.send(:undef_method, :restore_ruby_data_structure)
    end
    file
  end

  it 'maps every branch to the columns of its native descriptor, keyed by the branch itself' do
    expect(columns_by_type(source_file(path, live_coverage))).to eq(then: [21, 25], else: [28, 32])
  end

  it 'decodes stringified descriptors with the installed SimpleCov decoder' do
    expect(columns_by_type(stringified_file)).to eq(then: [21, 25], else: [28, 32])
  end

  it 'prefers RubyDataParser (SimpleCov >= 1.0) for stringified descriptors' do
    file = stringified_file
    parser = ruby_data_parser_spy(file)
    columns_by_type(file)
    expect(parser).to have_received(:call).with(then_arm.to_s)
  end

  it 'falls back to restore_ruby_data_structure (SimpleCov < 1.0) when RubyDataParser is absent' do
    file = stringified_file
    hide_const('SimpleCov::SourceFile::RubyDataParser')
    unless file.respond_to?(:restore_ruby_data_structure, true)
      lookup = { then_arm.to_s => then_arm, else_arm.to_s => else_arm, condition.to_s => condition }
      file.define_singleton_method(:restore_ruby_data_structure) { |descriptor| lookup.fetch(descriptor) }
    end
    expect(columns_by_type(file)).to eq(then: [21, 25], else: [28, 32])
  end

  it 'leaves branches without columns when no decoder is available' do
    expect(described_class.enrich(without_any_decoder(stringified_file))).to eq({})
  end

  it 'never modifies the SimpleCov branch objects' do
    file = source_file(path, live_coverage)
    described_class.enrich(file)
    expect(file.branches.map(&:instance_variables).flatten.uniq).not_to include(:@start_col, :@end_col)
  end

  it 'ignores coverage data whose branches entry is not a hash' do
    expect(described_class.enrich(source_file(path, { 'lines' => [1, 1, nil], 'branches' => [] }))).to eq({})
  end

  it 'ignores non-hash arm entries' do
    nil_arms = { 'lines' => [1, 1, nil], 'branches' => { condition => nil } }
    expect(described_class.enrich(source_file(path, nil_arms))).to eq({})
  end

  it 'ignores descriptors that are too short to carry column data' do
    short = { 'lines' => [1, 1, nil], 'branches' => { [:if, 0, 2, 0, 2, 0] => { [:then, 1, 2] => 0 } } }
    expect(described_class.enrich(source_file(path, short))).to eq({})
  end

  it 'ignores descriptors that decode to something other than an array' do
    odd = { 'lines' => [1, 1, nil], 'branches' => { condition => { 42 => 0 } } }
    expect(described_class.enrich(source_file(path, odd))).to eq({})
  end

  it 'yields an empty map when the coverage data cannot be read at all' do
    expect(described_class.enrich(source_file(path, []))).to eq({})
  end
end
