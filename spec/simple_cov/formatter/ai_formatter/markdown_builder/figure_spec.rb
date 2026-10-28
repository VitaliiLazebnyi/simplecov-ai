# typed: false
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SimpleCov::Formatter::AIFormatter::MarkdownBuilder::Figure do
  describe '.ratio' do
    it 'is the covered share in percent' do
      expect(described_class.ratio(1, 4)).to eq(25.0)
    end

    it 'is 100% when there is nothing to cover' do
      expect(described_class.ratio(0, 0)).to eq(100.0)
    end

    it 'is nil when either count is missing (the criterion is not measured)' do
      expect([described_class.ratio(nil, 4), described_class.ratio(1, nil), described_class.ratio(nil, nil)])
        .to eq([nil, nil, nil])
    end
  end

  describe '.read' do
    it 'keeps the percentage the block returns, nil included' do
      expect([described_class.read { 12.5 }.label, described_class.read { nil }.label]).to eq(['12.5%', nil])
    end

    it 'stands in an undecodable figure when the block raises' do
      expect(described_class.read { raise ArgumentError }.label).to eq(described_class::UNDECODABLE_LABEL)
    end
  end

  describe '#passing?' do
    it 'passes a perfect or an unmeasured figure only' do
      verdicts = [100.0, nil, 99.99, Float::NAN].map { |percent| described_class.new(percent).passing? }
      expect(verdicts).to eq([true, true, false, false])
    end
  end

  describe '#label' do
    it 'floors to one decimal' do
      expect([described_class.new(99.96).label, described_class.new(0.0).label]).to eq(['99.9%', '0.0%'])
    end
  end

  describe '#line' do
    it 'fills the label into the template, and gives no line for an unmeasured figure' do
      expect([described_class.new(50.0).line("[%<figure>s]\n"), described_class.new(nil).line('%<figure>s')])
        .to eq(["[50.0%]\n", nil])
    end
  end
end
