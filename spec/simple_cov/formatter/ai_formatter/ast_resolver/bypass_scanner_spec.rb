# typed: false
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SimpleCov::Formatter::AIFormatter::ASTResolver::BypassScanner do
  def node(name, start_line, end_line, type: 'Instance Method')
    SimpleCov::Formatter::AIFormatter::ASTResolver::SemanticNode.new(
      name: name, type: type, start_line: start_line, end_line: end_line
    )
  end

  let(:root) { SimpleCov::Formatter::AIFormatter::ASTResolver::SemanticNode.root(20) }
  let(:klass) { node('Runner', 3, 18, type: 'Class') }
  let(:first_method) { node('Runner#first', 4, 8) }
  let(:second_method) { node('Runner#second', 10, 14) }
  let(:nodes) { [root, klass, first_method, second_method] }

  def names_with_reasons(reasons_by_node)
    reasons_by_node.map { |semantic_node, reasons| [semantic_node.name, reasons] }
  end

  it 'attributes a region to the outermost nodes it fully contains, not to their ancestors' do
    reasons = described_class.attribute(nodes, [[4..14, '# :nocov:']])
    expect(names_with_reasons(reasons)).to eq([['Runner#first', ['# :nocov:']], ['Runner#second', ['# :nocov:']]])
  end

  it 'attributes a region inside a single node to that innermost node' do
    expect(names_with_reasons(described_class.attribute(nodes, [[5..6, '# simplecov:disable']])))
      .to eq([['Runner#first', ['# simplecov:disable']]])
  end

  it 'attributes a region wrapping only top-level code to the root scope' do
    expect(names_with_reasons(described_class.attribute(nodes, [[1..2, '# :nocov:']]))).to eq([['main', ['# :nocov:']]])
  end

  it 'lists a reason once per node even when several regions in that node carry it' do
    regions = [[5..5, '# simplecov:disable branch'], [7..7, '# simplecov:disable branch'], [6..6, '# :nocov:']]
    expect(names_with_reasons(described_class.attribute(nodes, regions)))
      .to eq([['Runner#first', ['# simplecov:disable branch', '# :nocov:']]])
  end

  it 'leaves a region alone when no node encloses it, as with a node list lacking a root scope' do
    expect(described_class.attribute([first_method], [[1..2, '# :nocov:']])).to eq({})
  end

  it 'never mutates the nodes it attributes to' do
    before = nodes.map { |semantic_node| [semantic_node.name, semantic_node.start_line, semantic_node.end_line] }
    described_class.attribute(nodes, [[4..14, '# :nocov:']])
    after = nodes.map { |semantic_node| [semantic_node.name, semantic_node.start_line, semantic_node.end_line] }
    expect(after).to eq(before)
  end
end
