# typed: false
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SimpleCov::Formatter::AIFormatter::MarkdownBuilder::BranchEnricher do
  # A minimal stand-in for a SimpleCov branch that records column enrichment.
  def branch(type:, start_line:, end_line:)
    instance_double(SimpleCov::SourceFile::Branch, type: type, start_line: start_line, end_line: end_line)
  end

  def source_file(coverage_data:, branches:)
    file = instance_double(SimpleCov::SourceFile, branches: branches)
    has_data = !coverage_data.equal?(:absent)
    allow(file).to receive(:respond_to?).with(:coverage_data).and_return(has_data)
    allow(file).to receive(:coverage_data).and_return(coverage_data) if has_data
    file
  end

  it 'applies native array column offsets to the matching branch' do
    br = branch(type: :then, start_line: 10, end_line: 10)
    file = source_file(
      coverage_data: { 'branches' => { [:if, 0, 10, 4, 10, 20] => { [:then, 1, 10, 4, 10, 20] => 0 } } },
      branches: [br]
    )

    described_class.enrich(file)

    expect([br.instance_variable_get(:@start_col), br.instance_variable_get(:@end_col)]).to eq([4, 20])
  end

  it 'decodes stringified descriptors via restore_ruby_data_structure on simplecov < 1.0' do
    br = branch(type: :then, start_line: 10, end_line: 10)
    file = source_file(
      coverage_data: { 'branches' => { '[:if, 0, 10, 4, 10, 20]' => { '[:then, 1, 10, 4, 10, 20]' => 0 } } },
      branches: [br]
    )
    allow(file).to receive(:respond_to?).with(:restore_ruby_data_structure, true).and_return(true)
    allow(file).to receive(:send).with(:restore_ruby_data_structure, '[:then, 1, 10, 4, 10, 20]')
                                 .and_return([:then, 1, 10, 4, 10, 20])

    described_class.enrich(file)

    expect(br.instance_variable_get(:@start_col)).to eq(4)
  end

  it 'leaves a stringified descriptor undecoded when the file offers no decoder' do
    br = branch(type: :then, start_line: 10, end_line: 10)
    file = source_file(
      coverage_data: { 'branches' => { '[:if, 0, 10, 4, 10, 20]' => { '[:then, 1, 10, 4, 10, 20]' => 0 } } },
      branches: [br]
    )
    allow(file).to receive(:respond_to?).with(:restore_ruby_data_structure, true).and_return(false)

    described_class.enrich(file)

    expect(br.instance_variable_get(:@start_col)).to be_nil
  end

  it 'leaves a branch untouched when no descriptor matches it' do
    br = branch(type: :else, start_line: 99, end_line: 99)
    file = source_file(
      coverage_data: { 'branches' => { [:if, 0, 10, 4, 10, 20] => { [:then, 1, 10, 4, 10, 20] => 0 } } },
      branches: [br]
    )

    described_class.enrich(file)

    expect(br.instance_variable_get(:@start_col)).to be_nil
  end

  it 'returns early when the file exposes no coverage data' do
    file = source_file(coverage_data: :absent, branches: [])
    expect { described_class.enrich(file) }.not_to raise_error
  end

  it 'ignores coverage data that is not a hash' do
    br = branch(type: :then, start_line: 10, end_line: 10)
    file = source_file(coverage_data: 'not a hash', branches: [br])

    described_class.enrich(file)

    expect(br.instance_variable_get(:@start_col)).to be_nil
  end

  it 'ignores coverage data whose branches entry is not a hash' do
    br = branch(type: :then, start_line: 10, end_line: 10)
    file = source_file(coverage_data: { 'branches' => [] }, branches: [br])

    described_class.enrich(file)

    expect(br.instance_variable_get(:@start_col)).to be_nil
  end

  it 'ignores non-hash inner branch entries' do
    br = branch(type: :then, start_line: 10, end_line: 10)
    file = source_file(coverage_data: { 'branches' => { [:if, 0, 10, 4, 10, 20] => nil } }, branches: [br])

    described_class.enrich(file)

    expect(br.instance_variable_get(:@start_col)).to be_nil
  end

  it 'ignores descriptors that are too short to carry column data' do
    br = branch(type: :then, start_line: 10, end_line: 10)
    file = source_file(coverage_data: { 'branches' => { [:if, 0] => { [:then, 1, 10] => 0 } } }, branches: [br])

    described_class.enrich(file)

    expect(br.instance_variable_get(:@start_col)).to be_nil
  end

  it 'swallows errors raised while reading coverage data' do
    file = instance_double(SimpleCov::SourceFile)
    allow(file).to receive(:respond_to?).with(:coverage_data).and_return(true)
    allow(file).to receive(:coverage_data).and_raise(RuntimeError, 'boom')

    expect { described_class.enrich(file) }.not_to raise_error
  end
end
