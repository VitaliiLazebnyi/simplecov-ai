# typed: false
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SimpleCov::Formatter::AIFormatter::ASTResolver::NodeChildren do
  def node(type, *children)
    Parser::AST::Node.new(type, children)
  end

  # A node of the `ast` gem that is not a Parser node: the resolver only ever descends into
  # Parser's own nodes.
  let(:foreign) { AST::Node.new(:foreign) }
  let(:const) { node(:const, nil, :Alpha) }
  let(:casgn) { node(:casgn, nil, :Beta, const) }

  describe '.nodes' do
    it 'returns the children that are Parser nodes, in order' do
      parent = node(:begin, const, :name, nil, foreign, casgn, 'text')
      expect(described_class.nodes(parent)).to eq([const, casgn])
    end
  end

  describe '.node_at' do
    it 'returns the node at the index' do
      expect(described_class.node_at(casgn, 2)).to equal(const)
    end

    it 'returns nil for an absent child, a name and a node that is not a Parser node' do
      parent = node(:begin, nil, :name, foreign)
      expect([0, 1, 2, 3].map { |index| described_class.node_at(parent, index) }).to eq([nil, nil, nil, nil])
    end
  end

  describe '.required_node_at' do
    it 'returns the node at the index' do
      expect(described_class.required_node_at(casgn, 2)).to equal(const)
    end

    it 'raises TypeError naming the node when the child is not a node' do
      expect { described_class.required_node_at(casgn, 1) }
        .to raise_error(TypeError, 'child 1 of a :casgn node is not a node')
    end
  end

  describe '.symbol_at' do
    it 'returns the Symbol at the index' do
      expect(described_class.symbol_at(casgn, 1)).to eq(:Beta)
    end

    it 'raises TypeError for an absent child' do
      expect { described_class.symbol_at(casgn, 5) }
        .to raise_error(TypeError, 'child 5 of a :casgn node is not a Symbol')
    end

    it 'raises TypeError naming the node when the child is not a Symbol' do
      expect { described_class.symbol_at(casgn, 2) }
        .to raise_error(TypeError, 'child 2 of a :casgn node is not a Symbol')
    end
  end

  describe '.literal_value' do
    it 'returns the value of a Symbol or String literal as a String' do
      expect([node(:sym, :run), node(:str, 'stop')].map { |literal| described_class.literal_value(literal) })
        .to eq(%w[run stop])
    end

    it 'reads the first child of the literal' do
      expect(described_class.literal_value(node(:str, 'first', 'second'))).to eq('first')
    end

    it 'raises TypeError for a literal node without a value' do
      expect { described_class.literal_value(node(:sym)) }
        .to raise_error(TypeError, 'child 0 of a :sym node is not a Symbol or String')
    end

    it 'raises TypeError naming the node when the value is neither' do
      expect { described_class.literal_value(node(:int, 1)) }
        .to raise_error(TypeError, 'child 0 of a :int node is not a Symbol or String')
    end
  end
end
