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
end
