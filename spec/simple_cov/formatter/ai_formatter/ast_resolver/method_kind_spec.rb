# Copyright (c) 2026 Vitalii Lazebnyi
# typed: false
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe(SimpleCov::Formatter::AIFormatter::ASTResolver::MethodKind) do
  let(:ast) { parse("\ndef run\n  1\nend\n") }

  def parse(source)
    buffer = Parser::Source::Buffer.new('(spec)', source: source)
    SimpleCov::Formatter::AIFormatter::ASTResolver::ParserBackend.parse(buffer)
  end

  def described(node)
    [node.name, node.type, node.line_range, node.method_name]
  end

  describe '#node_for' do
    it 'names an instance method Owner#name and a singleton method Owner.name' do
      kinds = [described_class::INSTANCE, described_class::SINGLETON]
      expect(kinds.map { |kind| described(kind.node_for(ast, 'Outer::Inner', 'run')) }).to(
        eq(
          [
            ['Outer::Inner#run', 'Instance Method', 2..4, 'run'],
            ['Outer::Inner.run', 'Singleton Method', 2..4, 'run']
          ]
        )
      )
    end

    it 'gives a top-level method the owner Ruby gives it: Object for a def, main for a singleton def' do
      names = [described_class::INSTANCE, described_class::SINGLETON].map { |kind| kind.node_for(ast, '', 'run').name }
      expect(names).to(eq(['Object#run', 'main.run']))
    end
  end
end
