# typed: false
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SimpleCov::Formatter::AIFormatter::ASTResolver::SemanticNode do
  def parse(source)
    buffer = Parser::Source::Buffer.new('(spec)', source: source)
    SimpleCov::Formatter::AIFormatter::ASTResolver::ParserBackend.parse(buffer)
  end

  def method_node(start_line, method_name)
    described_class.new(name: "A##{method_name}", type: 'Instance Method', start_line: start_line, end_line: 9,
                        method_name: method_name)
  end

  describe '.root' do
    it 'spans the whole file as main, an empty file still line 1' do
      roots = [described_class.root(12), described_class.root(0)]
      expect(roots.map { |root| [root.name, root.type, root.line_range] })
        .to eq([['main', 'Root Script Scope', 1..12], ['main', 'Root Script Scope', 1..1]])
    end
  end

  describe '.spanning' do
    it 'spans the lines of the AST node, without a method name' do
      ast = parse("\nclass A\n  1\nend\n")
      node = described_class.spanning(ast, name: 'A', type: 'Class')
      expect([node.name, node.type, node.line_range, node.method_name]).to eq(['A', 'Class', 2..4, nil])
    end
  end

  describe '#defines?' do
    it 'is true for the method starting on the line under the name' do
      expect(method_node(3, 'run').defines?(3, 'run')).to be(true)
    end

    it 'is false for another first line or another name' do
      node = method_node(3, 'run')
      expect([node.defines?(4, 'run'), node.defines?(3, 'stop')]).to eq([false, false])
    end

    it 'is false for a node without a method name' do
      expect(described_class.root(9).defines?(1, 'main')).to be(false)
    end
  end
end
