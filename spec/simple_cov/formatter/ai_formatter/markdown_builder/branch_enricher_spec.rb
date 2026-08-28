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

  # The shape a result has after SimpleCov rebuilt it from .resultset.json.
  def stringified_file
    arms = { then_arm.to_s => 1, else_arm.to_s => 0 }
    source_file(path, { 'lines' => [1, 1, nil], 'branches' => { condition.to_s => arms } })
  end

  def columns_by_type(file)
    described_class.enrich(file).to_h { |branch, columns| [branch.type, columns] }
  end

  def sign_file(branches)
    source_file(path, { 'lines' => [1, 1, nil], 'branches' => branches })
  end

  # The `[start_col, end_col]` pair of a descriptor.
  def columns_of(descriptor)
    [descriptor[3], descriptor[5]]
  end

  it 'maps every branch to the columns of its native descriptor, keyed by the branch itself' do
    expect(columns_by_type(source_file(path, live_coverage))).to eq(then: [21, 25], else: [28, 32])
  end

  it 'decodes stringified descriptors with the installed SimpleCov decoder' do
    expect(columns_by_type(stringified_file)).to eq(then: [21, 25], else: [28, 32])
  end

  it 'picks the decoder of the installed SimpleCov' do
    ruby_data_parser = defined?(SimpleCov::SourceFile::RubyDataParser) ? true : false
    expected = ruby_data_parser ? described_class::RUBY_DATA_PARSER_DECODER : described_class::LEGACY_DECODER
    expect(described_class::DECODER).to equal(expected)
  end

  it 'decodes a stringified descriptor and returns a native array as it is' do
    file = source_file(path, live_coverage)
    decoded = [described_class::DECODER.call(file, then_arm.to_s), described_class::DECODER.call(file, then_arm)]
    expect(decoded).to eq([then_arm, then_arm])
  end

  it 'decodes through RubyDataParser where SimpleCov ships it' do
    lookup = { then_arm.to_s => then_arm }
    stub_const('SimpleCov::SourceFile::RubyDataParser',
               Module.new { define_singleton_method(:call) { |descriptor| lookup.fetch(descriptor) } })
    file = source_file(path, live_coverage)
    expect(described_class::RUBY_DATA_PARSER_DECODER.call(file, then_arm.to_s)).to eq(then_arm)
  end

  it 'decodes through the private restore_ruby_data_structure of SimpleCov < 1.0' do
    file = source_file(path, live_coverage)
    lookup = { then_arm.to_s => then_arm }
    file.define_singleton_method(:restore_ruby_data_structure) { |descriptor| lookup.fetch(descriptor) }
    file.singleton_class.send(:private, :restore_ruby_data_structure)
    expect(described_class::LEGACY_DECODER.call(file, then_arm.to_s)).to eq(then_arm)
  end

  it 'hands every arm descriptor, with its file, to the decoder' do
    received = []
    stub_const("#{described_class}::DECODER", lambda { |file, descriptor|
      received << [file.filename, descriptor]
      { then_arm.to_s => then_arm, else_arm.to_s => else_arm }.fetch(descriptor)
    })
    columns = columns_by_type(stringified_file)
    expect([columns, received])
      .to eq([{ then: [21, 25], else: [28, 32] }, [[path, then_arm.to_s], [path, else_arm.to_s]]])
  end

  it 'ignores a descriptor the decoder cannot turn into an array' do
    stub_const("#{described_class}::DECODER", ->(_file, _descriptor) {})
    expect(columns_by_type(stringified_file)).to eq({})
  end

  it 'matches descriptors to branches by type, start and end line, whatever order SimpleCov lists them in' do
    arms = [[:then, 1, 2, 4, 2, 9], [:then, 2, 2, 11, 4, 3], [:then, 3, 3, 2, 4, 5]]
    branches = arms.each_with_index.to_h { |arm, index| [[:if, index * 4, arm[2], 0, 4, 0], { arm => 0 }] }
    coverage = { 'lines' => [1, 1, 1, 1, 1], 'branches' => branches }
    file = source_file(write_source(tmpdir, 'arms.rb', "1\n2\n3\n4\n5\n"), coverage)
    allow(file).to receive(:branches).and_return(file.branches.reverse)
    columns = described_class.enrich(file).to_h { |branch, cols| [[branch.start_line, branch.end_line], cols] }
    expect(columns).to eq([2, 2] => [4, 9], [2, 4] => [11, 3], [3, 4] => [2, 5])
  end

  it 'assigns columns in descriptor order to arms sharing type and line (two conditionals on one line)' do
    line = "def pick(a, b)\n  [a ? 1 : 2, b ? 3 : 4]\nend\n"
    first = %w[1 2].zip(%i[then else], [1, 2]).map { |text, type, id| branch_descriptor(line, type, id, 2, text) }
    second = %w[3 4].zip(%i[then else], [3, 4]).map { |text, type, id| branch_descriptor(line, type, id, 2, text) }
    branches = { branch_descriptor(line, :if, 0, 2, 'a ? 1 : 2') => first.zip([1, 0]).to_h,
                 branch_descriptor(line, :if, 2, 2, 'b ? 3 : 4') => second.zip([1, 0]).to_h }
    file = source_file(write_source(tmpdir, 'pair.rb', line), { 'lines' => [1, 1, nil], 'branches' => branches })
    expect(described_class.enrich(file).values_at(*file.branches)).to eq((first + second).map { |arm| columns_of(arm) })
  end

  it 'leaves a branch whose descriptor is too short for column data out of the map but keeps its siblings' do
    short_then = then_arm.first(5)
    expect(columns_by_type(sign_file({ condition => { short_then => 1, else_arm => 0 } }))).to eq(else: [28, 32])
  end

  it 'accepts descriptors carrying more than the six documented entries' do
    arms = { then_arm + [:extra] => 1, else_arm + [:extra] => 0 }
    expect(columns_by_type(sign_file({ condition => arms }))).to eq(then: [21, 25], else: [28, 32])
  end

  it 'never modifies the SimpleCov branch objects' do
    file = source_file(path, live_coverage)
    described_class.enrich(file)
    expect(file.branches.map(&:instance_variables).flatten.uniq).not_to include(:@start_col, :@end_col)
  end

  it 'yields an empty map for a branches entry that is not a hash' do
    expect(columns_by_type(sign_file([]))).to eq({})
  end

  it 'leaves the branches without columns when an arm map is a list of pairs rather than a hash' do
    expect(columns_by_type(sign_file({ condition => [[then_arm, 1], [else_arm, 0]] }))).to eq({})
  end

  it 'raises like SimpleCov for arms SimpleCov cannot build branches from' do
    expect { described_class.enrich(sign_file({ condition => nil })) }.to raise_error(NoMethodError)
  end

  it 'raises like SimpleCov for coverage data that is not a hash, leaving the file to the decode guard' do
    expect { described_class.enrich(source_file(path, [])) }.to raise_error(TypeError)
  end

  # SimpleCov >= 1.0's parser rejects a descriptor that is not an array literal; the eval of
  # older releases rejects a non-String just as SimpleCov's own branch building does.
  it 'raises like SimpleCov for a descriptor that is not an array' do
    error = defined?(SimpleCov::SourceFile::RubyDataParser) ? ArgumentError : TypeError
    expect { described_class.enrich(sign_file({ condition => { 42 => 0 } })) }.to raise_error(error)
  end
end
