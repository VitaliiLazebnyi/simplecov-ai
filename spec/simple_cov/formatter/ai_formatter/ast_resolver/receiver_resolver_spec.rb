# typed: false
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SimpleCov::Formatter::AIFormatter::ASTResolver::ReceiverResolver do
  def node(type, *children)
    Parser::AST::Node.new(type, children)
  end

  describe '.singleton_class_name' do
    it 'names a variable receiver by its name, the first child of the node' do
      expect([described_class.singleton_class_name(node(:lvar, :target, :extra)),
              described_class.singleton_class_name(node(:ivar, :@registry))]).to eq(%w[target @registry])
    end

    it 'names a constant receiver by its full path' do
      const = node(:const, node(:const, nil, :Outer), :Inner)
      expect(described_class.singleton_class_name(const)).to eq('Outer::Inner')
    end

    it 'names no other receiver' do
      expect(described_class.singleton_class_name(node(:send, nil, :target))).to be_nil
    end
  end

  describe '.singleton_method_receiver' do
    it 'is the constant receiver, or the enclosing context for any other receiver' do
      expect([described_class.singleton_method_receiver(node(:const, nil, :Other), 'A'),
              described_class.singleton_method_receiver(node(:self), 'A')]).to eq(%w[Other A])
    end
  end
end
