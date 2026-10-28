# typed: false
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SimpleCov::Formatter::AIFormatter::LineSpan do
  describe '.encloses?' do
    it 'is true for an inner range inside the outer, including one sharing both ends' do
      verdicts = [described_class.encloses?(3..18, 10..14), described_class.encloses?(3..18, 3..18),
                  described_class.encloses?(3..18, 10..18), described_class.encloses?(3..18, 3..5)]
      expect(verdicts).to eq([true, true, true, true])
    end

    it 'is false when the inner range starts before or ends after the outer' do
      verdicts = [described_class.encloses?(3..18, 2..5), described_class.encloses?(3..18, 10..19),
                  described_class.encloses?(10..14, 3..5)]
      expect(verdicts).to eq([false, false, false])
    end
  end

  describe '.strictly_encloses?' do
    it 'is true for an enclosed range spanning fewer lines, wherever it sits' do
      verdicts = [described_class.strictly_encloses?(3..18, 10..14), described_class.strictly_encloses?(3..18, 3..5),
                  described_class.strictly_encloses?(3..18, 10..18), described_class.strictly_encloses?(3..18, 4..18)]
      expect(verdicts).to eq([true, true, true, true])
    end

    it 'is false for an identical span, a wider span or a range outside the outer' do
      verdicts = [described_class.strictly_encloses?(3..18, 3..18), described_class.strictly_encloses?(3..5, 3..18),
                  described_class.strictly_encloses?(10..14, 3..5), described_class.strictly_encloses?(3..3, 3..3)]
      expect(verdicts).to eq([false, false, false, false])
    end
  end

  describe '.of' do
    it 'spans a branch, a node or a method deficit from its first to its last line' do
      branch = SimpleCov::SourceFile::Branch.new(start_line: 4, end_line: 6, coverage: 0, inline: false, type: :then)
      node = SimpleCov::Formatter::AIFormatter::ASTResolver::SemanticNode.new(
        name: 'A', type: 'Class', start_line: 1, end_line: 9
      )
      expect([described_class.of(branch), described_class.of(node)]).to eq([4..6, 1..9])
    end
  end

  describe '.line' do
    it 'is the range of one line' do
      expect(described_class.line(7)).to eq(7..7)
    end
  end

  describe '.label' do
    it 'labels a single line by its number and a span by its bounds, as strings' do
      expect([described_class.label(12..12), described_class.label(12..15)]).to eq(%w[12 12-15])
    end
  end

  describe '.sort_key' do
    it 'orders by first line, then wider ranges first' do
      expect([3..9, 1..2, 3..12].sort_by { |range| described_class.sort_key(range) }).to eq([1..2, 3..12, 3..9])
    end
  end
end
