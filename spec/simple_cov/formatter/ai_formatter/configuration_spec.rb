# typed: false
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SimpleCov::Formatter::AIFormatter::Configuration do
  subject(:config) { described_class.new }

  describe 'defaults' do
    it 'uses the documented default report path' do
      expect(config.report_path).to eq('coverage/ai_report.md')
    end

    it 'defaults to fine granularity, bypasses on, console off' do
      expect([config.granularity, config.include_bypasses, config.output_to_console])
        .to eq([:fine, true, false])
    end
  end

  describe '#report_path=' do
    it 'accepts a non-empty path' do
      config.report_path = 'tmp/report.md'
      expect(config.report_path).to eq('tmp/report.md')
    end

    it 'rejects a blank path' do
      expect { config.report_path = '   ' }.to raise_error(ArgumentError, /report_path/)
    end
  end

  describe '#max_file_size_kb=' do
    it 'accepts a positive integer' do
      config.max_file_size_kb = 25
      expect(config.max_file_size_kb).to eq(25)
    end

    it 'rejects zero' do
      expect { config.max_file_size_kb = 0 }.to raise_error(ArgumentError, /max_file_size_kb/)
    end

    it 'rejects a negative value' do
      expect { config.max_file_size_kb = -5 }.to raise_error(ArgumentError, /positive/)
    end
  end

  describe '#max_snippet_lines=' do
    it 'accepts a positive integer' do
      config.max_snippet_lines = 3
      expect(config.max_snippet_lines).to eq(3)
    end

    it 'rejects a non-positive value' do
      expect { config.max_snippet_lines = 0 }.to raise_error(ArgumentError, /max_snippet_lines/)
    end
  end

  describe '#granularity=' do
    it 'accepts :fine and :coarse' do
      config.granularity = :coarse
      expect(config.granularity).to eq(:coarse)
    end

    it 'rejects an unknown granularity' do
      expect { config.granularity = :medium }.to raise_error(ArgumentError, /granularity/)
    end
  end

  describe '#output_to_console= and #include_bypasses=' do
    it 'toggles the boolean flags' do
      config.output_to_console = true
      config.include_bypasses = false
      expect([config.output_to_console, config.include_bypasses]).to eq([true, false])
    end
  end
end
