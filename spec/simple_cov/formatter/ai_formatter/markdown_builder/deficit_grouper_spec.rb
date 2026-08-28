# typed: false
# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'

RSpec.describe SimpleCov::Formatter::AIFormatter::MarkdownBuilder::DeficitGrouper do
  let(:tmpdir) { Dir.mktmpdir('scai') }
  let(:path) { write_source(tmpdir, 'grouped.rb', Array.new(12) { |index| "line #{index + 1}\n" }.join) }

  after { FileUtils.remove_entry(tmpdir) }

  def node(name, start_line, end_line)
    SimpleCov::Formatter::AIFormatter::ASTResolver::SemanticNode.new(
      name: name, type: 'Instance Method', start_line: start_line, end_line: end_line
    )
  end

  def file_with(missed_lines: [], branches: {}, methods: {})
    coverage = { 'lines' => line_hits(12, missed: missed_lines), 'branches' => branches, 'methods' => methods }
    file = source_file(path, coverage)
    emulate_method_coverage!(file, methods) unless method_coverage_supported?
    file
  end

  def build(file, nodes)
    described_class.build(file, nodes, SimpleCov::Formatter::AIFormatter::MarkdownBuilder::MethodDeficit.from_file(file))
  end

  def arm(type, start_line, end_line = start_line)
    multiline_branch_descriptor(type, 1, start_line, end_line)
  end

  def group_names(groups)
    groups.values.map { |deficit_group| deficit_group.semantic_node.name }
  end

  it 'keeps same-named methods redefined in one file as separate groups' do
    groups = build(file_with(missed_lines: [2, 6]), [node('Dup#run', 1, 3), node('Dup#run', 5, 7)])
    expect(groups.values.map { |deficit_group| deficit_group.semantic_node.start_line }).to contain_exactly(1, 5)
  end

  it 'groups deficits belonging to the same node together' do
    groups = build(file_with(missed_lines: [2, 3]), [node('Solo#work', 1, 5)])
    expect([groups.size, groups.values.first.lines.map(&:line_number)]).to eq([1, [2, 3]])
  end

  it 'orders an enclosing node before a method opening on its line, whatever the deficit order' do
    nodes = [node('Outer', 3, 10), node('Outer#inner', 3, 5)]
    forward = build(file_with(missed_lines: [4, 8]), nodes)
    backward = build(file_with(missed_lines: [8, 4]), nodes)
    expect([group_names(forward), group_names(backward)]).to eq([%w[Outer Outer#inner], %w[Outer Outer#inner]])
  end

  it 'labels a deficit no node spans by position, merging a line and a single-line branch there' do
    file = file_with(missed_lines: [9], branches: { arm(:if, 9) => { arm(:then, 9) => 0 } })
    groups = build(file, [node('Solo#work', 1, 5)])
    summary = groups.transform_values do |deficit_group|
      [deficit_group.semantic_node, deficit_group.lines.size, deficit_group.branches.size]
    end
    expect(summary).to eq('Line 9' => [nil, 1, 1])
  end

  it 'labels a multi-line branch no node spans by its range and sorts positional groups by line' do
    file = file_with(missed_lines: [12], branches: { arm(:if, 9, 11) => { arm(:then, 9, 11) => 0 } })
    expect(build(file, [node('Solo#work', 1, 5)]).keys).to eq(['Lines 9-11', 'Line 12'])
  end

  it 'attaches a missed method to the innermost node spanning its definition' do
    methods = { ['Klass', :inner, 3, 2, 5, 5] => 0, ['Klass', :outer, 7, 2, 9, 5] => 2 }
    groups = build(file_with(methods: methods), [node('Klass', 1, 10), node('Klass#inner', 3, 5)])
    expect(groups.transform_values { |deficit_group| deficit_group.method_deficits.map(&:name) })
      .to eq('Klass#inner@3' => ['Klass#inner'])
  end

  it 'builds the node-less raw group from every deficit SimpleCov reports' do
    methods = { ['Klass', :gone, 3, 2, 5, 5] => 0 }
    file = file_with(missed_lines: [4], branches: { arm(:if, 4) => { arm(:else, 4) => 0 } }, methods: methods)
    raw = described_class.raw_group(file, SimpleCov::Formatter::AIFormatter::MarkdownBuilder::MethodDeficit.from_file(file))
    expect([raw.semantic_node, raw.lines.size, raw.branches.size, raw.method_deficits.map(&:name)])
      .to eq([nil, 1, 1, ['Klass#gone']])
  end
end
