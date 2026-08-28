# typed: false
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SimpleCov::Formatter::AIFormatter::MarkdownBuilder::DecodeGuard do
  describe '.attempt' do
    it 'returns the value of a block that decodes' do
      expect(described_class.attempt(:fallback) { :decoded }).to eq(:decoded)
    end

    it 'returns the fallback for the eval SyntaxError of SimpleCov < 1.0, which is not a StandardError' do
      expect(described_class.attempt(:fallback) { raise SyntaxError, 'unexpected end-of-input' }).to eq(:fallback)
    end

    it 'returns the fallback for the ArgumentError of SimpleCov >= 1.0' do
      expect(described_class.attempt(:fallback) { raise ArgumentError, 'expected array literal' }).to eq(:fallback)
    end

    it 'lets signals and other non-error exceptions through' do
      expect { described_class.attempt(:fallback) { raise Interrupt } }.to raise_error(Interrupt)
    end
  end

  describe '.render' do
    it 'returns the fragments of a block that renders' do
      expect(described_class.render { ["- `A`\n"] }).to eq(["- `A`\n"])
    end

    it 'replaces the fragments with one error entry naming the eval SyntaxError of SimpleCov < 1.0' do
      expect(described_class.render { raise SyntaxError, 'unexpected end-of-input' })
        .to eq(["  - **ERROR:** SimpleCov could not decode this file's coverage data (SyntaxError); skipped.\n"])
    end

    it 'replaces the fragments with one error entry naming a StandardError' do
      expect(described_class.render { raise TypeError, 'nil is not an Integer' })
        .to eq(["  - **ERROR:** SimpleCov could not decode this file's coverage data (TypeError); skipped.\n"])
    end

    it 'lets signals and other non-error exceptions through' do
      expect { described_class.render { raise NoMemoryError } }.to raise_error(NoMemoryError)
    end
  end
end
