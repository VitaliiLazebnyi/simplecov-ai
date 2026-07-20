# typed: false
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SimpleCov::Formatter::AIFormatter::MarkdownBuilder::DeficitGrouper do
  def node(name, start_line, end_line)
    SimpleCov::Formatter::AIFormatter::ASTResolver::SemanticNode.new(
      name: name, type: 'Instance Method', start_line: start_line, end_line: end_line, bypass_reasons: []
    )
  end

  def source_file(missed_lines)
    file = instance_double(SimpleCov::SourceFile, missed_lines: missed_lines)
    allow(file).to receive(:respond_to?).with(:branches).and_return(false)
    file
  end

  it 'keeps same-named methods redefined in one file as separate groups' do
    nodes = [node('Dup#run', 1, 3), node('Dup#run', 5, 7)]
    missed = [instance_double(SimpleCov::SourceFile::Line, line_number: 2),
              instance_double(SimpleCov::SourceFile::Line, line_number: 6)]

    groups = described_class.build(source_file(missed), nodes)

    expect(groups.values.map { |group| group.semantic_node.start_line }).to contain_exactly(1, 5)
  end

  it 'groups deficits belonging to the same node together' do
    nodes = [node('Solo#work', 1, 5)]
    missed = [instance_double(SimpleCov::SourceFile::Line, line_number: 2),
              instance_double(SimpleCov::SourceFile::Line, line_number: 3)]

    groups = described_class.build(source_file(missed), nodes)

    expect([groups.size, groups.values.first.lines.size]).to eq([1, 2])
  end
end
