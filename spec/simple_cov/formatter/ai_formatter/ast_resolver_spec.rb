# typed: false
# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe SimpleCov::Formatter::AIFormatter::ASTResolver do
  let(:tmpdir) { Dir.mktmpdir }
  let(:fixture_path) { File.expand_path('../../../fixtures/resolver_constructs.rb', __dir__) }

  after { FileUtils.remove_entry(tmpdir) }

  def resolve(code)
    path = File.join(tmpdir, 'sample.rb')
    File.binwrite(path, code)
    described_class.resolve(path)
  end

  def resolve_quietly(code)
    resolve(code)
  rescue Parser::SyntaxError
    nil
  end

  def node_table(nodes)
    nodes.map { |node| [node.name, node.type, node.start_line, node.end_line] }
  end

  describe '.resolve' do
    context 'with the resolver fixture' do
      let(:nodes) { described_class.resolve(fixture_path) }
      let(:expected_table) do
        [
          ['main', 'Root Script Scope', 1, 114],
          ['Versioned', 'Module', 14, 22],
          ['Versioned#version', 'Instance Method', 19, 21],
          ['Mixin', 'Module', 24, 28],
          ['Mixin#helper', 'Instance Method', 25, 27],
          ['Point', 'Struct', 30, 34],
          ['Point#distance', 'Instance Method', 31, 33],
          ['PAIR', 'Struct', 36, 36],
          ['Dynamic', 'Class', 39, 65],
          ['Dynamic#literal_symbol', 'Instance Method', 40, 42],
          ['Dynamic#braced', 'Instance Method', 44, 44],
          ['Dynamic#numbered', 'Instance Method', 46, 46],
          ['Dynamic.build', 'Singleton Method', 48, 50],
          ['Dynamic.singleton_scoped', 'Singleton Method', 63, 63],
          ['Delegator', 'Class', 68, 74],
          ['Delegator#relay', 'Instance Method', 69, 73],
          ['Registrar', 'Class', 77, 114],
          ['handler.assist', 'Singleton Method', 80, 82],
          ['Delegator.make', 'Singleton Method', 86, 88],
          ['Registrar#opaque', 'Instance Method', 92, 94],
          ['Registrar#initialize', 'Instance Method', 97, 99],
          ['Registrar#install', 'Instance Method', 101, 107],
          ['@store.lookup', 'Singleton Method', 103, 105],
          ['Registrar.registered', 'Singleton Method', 110, 112]
        ]
      end

      it 'derives the exact node table in source order, root scope first' do
        expect(node_table(nodes)).to eq(expected_table)
      end

      it 'attributes the top-level bypass region to the root scope alone' do
        bypassed = nodes.map { |node| [node.name, node.bypass_reasons] }.reject { |_name, reasons| reasons.empty? }
        expect(bypassed).to eq([['main', ['# simplecov:disable']]])
      end

      it 'marks only the first node as the root scope' do
        expect(nodes.map(&:root?)).to eq([true] + Array.new(nodes.size - 1, false))
      end
    end

    it 'returns an empty array for a missing file' do
      expect(described_class.resolve(File.join(tmpdir, 'missing.rb'))).to eq([])
    end

    it 'returns only a root scope spanning line 1 for an empty file' do
      expect(node_table(resolve(''))).to eq([['main', 'Root Script Scope', 1, 1]])
    end

    it 'spans every line of a comment-only file with the root scope' do
      expect(node_table(resolve("# one\n# two\n"))).to eq([['main', 'Root Script Scope', 1, 2]])
    end

    it 'counts a final line that lacks a trailing newline' do
      expect(node_table(resolve("def solo\nend"))).to eq([['main', 'Root Script Scope', 1, 2],
                                                          ['#solo', 'Instance Method', 1, 2]])
    end

    it 'names a define_method block by its string literal name' do
      nodes = resolve("class Named\n  define_method('by_string') { 1 }\nend\n")
      expect(node_table(nodes)).to eq([['main', 'Root Script Scope', 1, 3], ['Named', 'Class', 1, 3],
                                       ['Named#by_string', 'Instance Method', 2, 2]])
    end

    it 'treats define_method with an explicit self receiver like the receiverless form' do
      nodes = resolve("class Named\n  self.define_method(:explicit) do\n    1\n  end\nend\n")
      expect(node_table(nodes)).to eq([['main', 'Root Script Scope', 1, 5], ['Named', 'Class', 1, 5],
                                       ['Named#explicit', 'Instance Method', 2, 4]])
    end

    it 'leaves a block-less define_method call transparent' do
      nodes = resolve("class Named\n  define_method(:alias_like, instance_method(:other))\nend\n")
      expect(node_table(nodes)).to eq([['main', 'Root Script Scope', 1, 3], ['Named', 'Class', 1, 3]])
    end

    it 'recognizes a builder block written with the it parameter' do
      # Ruby 3.4 `it` blocks; older grammars parse the same source as an ordinary block.
      nodes = resolve("Q2 = Struct.new(:a) { it }\n")
      expect(node_table(nodes)).to eq([['main', 'Root Script Scope', 1, 1], ['Q2', 'Struct', 1, 1]])
    end

    it 'accepts string literals whose escapes are invalid in UTF-8, as MRI does' do
      nodes = resolve("class Bytes\n  def mask\n    \"\\xf0-\\xff\"\n  end\nend\n")
      expect(node_table(nodes)).to eq([['main', 'Root Script Scope', 1, 5], ['Bytes', 'Class', 1, 5],
                                       ['Bytes#mask', 'Instance Method', 2, 4]])
    end

    it 'honours an encoding magic comment for a non-UTF-8 source' do
      nodes = resolve("# encoding: Shift_JIS\nclass Kana\n  def read\n    '\x82\xa0'\n  end\nend\n".b)
      expect(node_table(nodes)).to eq([['main', 'Root Script Scope', 1, 6], ['Kana', 'Class', 2, 6],
                                       ['Kana#read', 'Instance Method', 3, 5]])
    end

    it 'keeps the structure of a file whose comments contain stray non-UTF-8 bytes' do
      nodes = resolve("# caf\xe9\nclass Latin\n  def read\n    1\n  end\nend\n".b)
      expect(node_table(nodes)).to eq([['main', 'Root Script Scope', 1, 6], ['Latin', 'Class', 2, 6],
                                       ['Latin#read', 'Instance Method', 3, 5]])
    end

    it 'raises Parser::SyntaxError for invalid Ruby' do
      expect { resolve("class Broken\nend def =") }.to raise_error(Parser::SyntaxError)
    end

    it 'prints no diagnostic to STDERR for invalid Ruby' do
      expect { resolve_quietly("class Broken\nend def =") }.not_to output.to_stderr
    end

    it 'prints no warning to STDERR for code the grammar merely warns about' do
      expect { resolve("def ambiguous\n  puts -1\nend\n") }.not_to output.to_stderr
    end
  end
end
