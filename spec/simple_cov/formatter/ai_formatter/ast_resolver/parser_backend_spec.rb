# typed: false
# frozen_string_literal: true

require 'spec_helper'
# The development bundle always provides Prism >= 1.2 (rubocop-ast depends on it), so the
# translation layer is loaded eagerly here and the examples can drive both backends on every
# Ruby, stubbing versions and constants to reach each fallback.
require 'prism'
require 'prism/translation/parser'

RSpec.describe SimpleCov::Formatter::AIFormatter::ASTResolver::ParserBackend do
  describe '.select_grammar' do
    it 'prefers the version-specific Prism grammar of each Ruby it knows' do
      grammars = %w[3.3.12 3.4.10 4.0.6 4.1.0].map { |ruby| described_class.select_grammar(ruby_version: ruby) }
      expect(grammars).to eq([Prism::Translation::Parser33, Prism::Translation::Parser34,
                              Prism::Translation::Parser40, Prism::Translation::Parser41])
    end

    it 'falls back to the base Prism grammar for a Ruby newer than any Prism knows' do
      expect(described_class.select_grammar(ruby_version: '9.9.9')).to eq(Prism::Translation::Parser)
    end

    it 'falls back to the base Prism grammar when an older Prism lacks the version class' do
      hide_const('Prism::Translation::Parser40')
      hide_const('Prism::Translation::Parser41')
      grammars = %w[4.0.6 4.1.0].map { |ruby| described_class.select_grammar(ruby_version: ruby) }
      expect(grammars).to eq([Prism::Translation::Parser, Prism::Translation::Parser])
    end

    it 'uses the exact parser gem grammar for Rubies older than the oldest Prism grammar' do
      grammars = %w[2.7.8 3.0.7 3.1.7 3.2.9].map { |ruby| described_class.select_grammar(ruby_version: ruby) }
      expect(grammars).to eq([Parser::Ruby27, Parser::Ruby30, Parser::Ruby31, Parser::Ruby32])
    end

    it 'selects the grammar of the running Ruby and installed parser gem by default' do
      expect(described_class.select_grammar).to eq(described_class::GRAMMAR)
    end

    it 'treats a parser gem version with fewer segments than the floor as below it' do
      expect(described_class.select_grammar(ruby_version: '3.4.10', parser_version: '3.3')).to eq(Parser::Ruby34)
    end

    it 'treats a Prism version with fewer segments than the floor as equal when the rest is zero' do
      stub_const('Prism::VERSION', '1.2')
      expect(described_class.select_grammar(ruby_version: '3.4.10')).to eq(Prism::Translation::Parser34)
    end

    it 'uses the exact parser gem grammar when the parser gem is too old for Prism translation' do
      grammars = %w[3.3.12 3.4.10].map do |ruby|
        described_class.select_grammar(ruby_version: ruby, parser_version: '3.1.0')
      end
      expect(grammars).to eq([Parser::Ruby33, Parser::Ruby34])
    end

    it 'uses the exact parser gem grammar when the installed Prism predates the translation layer' do
      stub_const('Prism::VERSION', '0.19.0')
      expect(described_class.select_grammar(ruby_version: '3.4.10')).to eq(Parser::Ruby34)
    end

    it 'uses the exact parser gem grammar when Prism cannot be required at all' do
      allow(described_class).to receive(:require).and_call_original
      allow(described_class).to receive(:require).with('prism').and_raise(LoadError)
      expect(described_class.select_grammar(ruby_version: '3.3.12')).to eq(Parser::Ruby33)
    end

    it 'loads parser/current for a Ruby the parser gem has no exact grammar for' do
      expect(described_class.select_grammar(ruby_version: '4.0.6', parser_version: '3.1.0')).to eq(Parser::CurrentRuby)
    end

    it 'loads parser/current for a Ruby older than the grammars it knows, even one the parser gem ships' do
      expect(described_class.select_grammar(ruby_version: '2.6.10', parser_version: '3.1.0')).to eq(Parser::CurrentRuby)
    end

    it 'loads parser/current when the listed grammar file is missing from the installed parser gem' do
      allow(described_class).to receive(:require).and_call_original
      allow(described_class).to receive(:require).with('parser/ruby34').and_raise(LoadError)
      expect(described_class.select_grammar(ruby_version: '3.4.10', parser_version: '3.1.0')).to eq(Parser::CurrentRuby)
    end

    it 'mutes the parser/current version-deviation warning' do
      expect { described_class.select_grammar(ruby_version: '9.9.9', parser_version: '3.1.0') }.not_to output.to_stderr
    end
  end

  describe '.parse' do
    def buffer_for(source)
      Parser::Source::Buffer.new('(spec)', source: source)
    end

    it 'returns nil for an empty buffer' do
      expect(described_class.parse(buffer_for(''))).to be_nil
    end

    it 'returns the root AST node of a parsable buffer' do
      expect(described_class.parse(buffer_for("def solo\nend\n")).type).to eq(:def)
    end

    it 'raises Parser::SyntaxError for a buffer that is not Ruby' do
      expect { described_class.parse(buffer_for('class')) }.to raise_error(Parser::SyntaxError)
    end

    it 'accepts string literals whose escapes are invalid in UTF-8, as MRI does' do
      expect(described_class.parse(buffer_for("\"\\xf0-\\xff\"\n")).type).to eq(:str)
    end

    it 'prints nothing for code the grammar merely warns about' do
      expect { described_class.parse(buffer_for("def ambiguous\n  puts -1\nend\n")) }.not_to output.to_stderr
    end

    it 'selects a Parser::Base grammar for the running Ruby at load time' do
      expect(described_class::GRAMMAR).to be < Parser::Base
    end
  end

  describe '.silence_warnings' do
    def silence_warnings(&block)
      described_class.send(:silence_warnings, &block)
    end

    def stderr_of
      original_stderr = $stderr
      $stderr = StringIO.new
      yield
      $stderr.string
    ensure
      $stderr = original_stderr
    end

    it 'runs the block, muting the Ruby warnings it raises' do
      executed = false
      printed = stderr_of do
        silence_warnings do
          warn 'noise'
          executed = true
        end
      end
      expect([printed, executed]).to eq(['', true])
    end

    def verbosities_after_silencing
      $VERBOSE = true
      silence_warnings { nil }
      after_success = $VERBOSE
      begin
        silence_warnings { raise LoadError, 'missing' }
      rescue LoadError
        nil
      end
      [after_success, $VERBOSE]
    end

    it 'restores the verbosity afterwards, even when the block raises' do
      verbosity = $VERBOSE
      begin
        expect(verbosities_after_silencing).to eq([true, true])
      ensure
        $VERBOSE = verbosity
      end
    end
  end
end
