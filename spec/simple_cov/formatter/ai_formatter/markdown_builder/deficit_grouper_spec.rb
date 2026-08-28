# typed: false
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SimpleCov::Formatter::AIFormatter::MarkdownBuilder::DeficitGrouper do
  def node(name, start_line, end_line)
    SimpleCov::Formatter::AIFormatter::ASTResolver::SemanticNode.new(
      name: name, type: 'Instance Method', start_line: start_line, end_line: end_line, bypass_reasons: []
    )
  end

  def line(line_number)
    instance_double(SimpleCov::SourceFile::Line, line_number: line_number)
  end

  def branch(start_line, end_line)
    instance_double(SimpleCov::SourceFile::Branch, start_line: start_line, end_line: end_line, type: :then)
  end

  def source_file(missed_lines, missed_branches = [])
    file = instance_double(SimpleCov::SourceFile, missed_lines: missed_lines, missed_branches: missed_branches,
                                                  branches: missed_branches)
    allow(file).to receive(:respond_to?).with(:branches).and_return(missed_branches.any?)
    file
  end

  def group_names(groups)
    groups.values.map { |deficit_group| deficit_group.semantic_node.name }
  end

  it 'keeps same-named methods redefined in one file as separate groups' do
    nodes = [node('Dup#run', 1, 3), node('Dup#run', 5, 7)]

    groups = described_class.build(source_file([line(2), line(6)]), nodes)

    expect(groups.values.map { |deficit_group| deficit_group.semantic_node.start_line }).to contain_exactly(1, 5)
  end

  it 'groups deficits belonging to the same node together' do
    nodes = [node('Solo#work', 1, 5)]

    groups = described_class.build(source_file([line(2), line(3)]), nodes)

    expect([groups.size, groups.values.first.lines.size]).to eq([1, 2])
  end

  it 'orders an enclosing node before a method opening on its line, whatever the deficit order' do
    nodes = [node('Outer', 3, 10), node('Outer#inner', 3, 5)]

    forward = described_class.build(source_file([line(4), line(8)]), nodes)
    backward = described_class.build(source_file([line(8), line(4)]), nodes)

    expect([group_names(forward), group_names(backward)]).to eq([%w[Outer Outer#inner], %w[Outer Outer#inner]])
  end

  it 'labels a deficit no node spans by position, merging a line and a single-line branch there' do
    groups = described_class.build(source_file([line(9)], [branch(9, 9)]), [node('Solo#work', 1, 5)])

    summary = groups.transform_values do |deficit_group|
      [deficit_group.semantic_node, deficit_group.lines.size, deficit_group.branches.size]
    end
    expect(summary).to eq('Line 9' => [nil, 1, 1])
  end

  it 'labels a multi-line branch no node spans by its range and sorts positional groups by line' do
    groups = described_class.build(source_file([line(12)], [branch(9, 11)]), [node('Solo#work', 1, 5)])

    expect(groups.keys).to eq(['Lines 9-11', 'Line 12'])
  end
end
