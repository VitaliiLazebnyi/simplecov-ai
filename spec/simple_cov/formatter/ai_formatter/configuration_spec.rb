# typed: false
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SimpleCov::Formatter::AIFormatter::Configuration do
  subject(:config) { described_class.new }

  describe 'defaults' do
    it 'reads the documented default report path and reports it as not configured' do
      expect([config.report_path, config.report_path_configured?]).to eq(['coverage/ai_report.md', false])
    end

    it 'declares every setting up front, the report path as unset' do
      expect(config.instance_variables).to eq(%i[@report_path @max_file_size_kb @max_snippet_lines @output_to_console
                                                 @granularity @include_bypasses])
    end

    it 'defaults to fine granularity, bypasses on, console off' do
      expect([config.granularity, config.include_bypasses, config.output_to_console])
        .to eq([:fine, true, false])
    end
  end

  describe '#report_path=' do
    it 'accepts a non-empty path and marks it configured' do
      config.report_path = 'tmp/report.md'
      expect([config.report_path, config.report_path_configured?]).to eq(['tmp/report.md', true])
    end

    it 'rejects a blank path' do
      expect { config.report_path = '   ' }.to raise_error(ArgumentError, /report_path/)
    end

    it 'rejects a path containing a NUL byte' do
      expect { config.report_path = "report\0.md" }.to raise_error(ArgumentError, /NUL/)
    end

    # The signature does the rejecting; mutant re-inserts methods without their `sig`, so the
    # example is excluded there.
    it 'rejects a non-String path at assignment', mutant: false do
      expect { config.report_path = :report }.to raise_error(TypeError)
    end
  end

  describe '#max_file_size_kb=' do
    it 'accepts a positive integer' do
      config.max_file_size_kb = 25
      expect(config.max_file_size_kb).to eq(25)
    end

    it 'rejects zero' do
      expect { config.max_file_size_kb = 0 }
        .to raise_error(ArgumentError, 'max_file_size_kb must be a positive Integer, got 0')
    end

    it 'rejects a negative value' do
      expect { config.max_file_size_kb = -5 }
        .to raise_error(ArgumentError, 'max_file_size_kb must be a positive Integer, got -5')
    end
  end

  describe '#max_snippet_lines=' do
    it 'accepts a positive integer' do
      config.max_snippet_lines = 3
      expect(config.max_snippet_lines).to eq(3)
    end

    it 'rejects a non-positive value' do
      expect { config.max_snippet_lines = 0 }
        .to raise_error(ArgumentError, 'max_snippet_lines must be a positive Integer, got 0')
    end
  end

  describe '#granularity=' do
    it 'accepts :fine and :coarse' do
      config.granularity = :coarse
      expect(config.granularity).to eq(:coarse)
    end

    it 'rejects an unknown granularity, naming the accepted ones' do
      expect { config.granularity = :medium }
        .to raise_error(ArgumentError, 'granularity must be one of [:fine, :coarse], got :medium')
    end
  end

  describe '#output_to_console= and #include_bypasses=' do
    it 'toggles the boolean flags' do
      config.output_to_console = true
      config.include_bypasses = false
      expect([config.output_to_console, config.include_bypasses]).to eq([true, false])
    end

    it 'rejects a non-boolean output_to_console at assignment instead of at report time' do
      expect { config.output_to_console = 'yes' }.to raise_error(TypeError, /output_to_console.*T::Boolean/)
    end

    it 'rejects a non-boolean include_bypasses at assignment' do
      expect { config.include_bypasses = nil }.to raise_error(TypeError, /include_bypasses/)
    end
  end
end
