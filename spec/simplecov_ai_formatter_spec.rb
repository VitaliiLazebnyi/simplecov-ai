# typed: false
# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'stringio'
require 'tmpdir'

RSpec.describe SimpleCov::Formatter::AIFormatter do
  let(:config) { described_class.configuration }

  before do
    described_class.instance_variable_set(:@configuration, nil)
    described_class.configure do |c|
      c.report_path = 'coverage/test_ai_report.md'
      c.output_to_console = false
      c.max_file_size_kb = 50
    end
  end

  after do
    FileUtils.rm_f(config.report_path)
  end

  describe '.configure' do
    it 'allows configuring the formatter' do
      described_class.configure { |c| c.max_file_size_kb = 10 }
      expect(config.max_file_size_kb).to eq(10)
    end

    it 'does nothing if no block is given' do
      expect { described_class.configure }.not_to raise_error
    end
  end

  describe '#format' do
    let(:formatter) { described_class.new }
    let(:mock_line) { instance_double(SimpleCov::SourceFile::Line, line_number: 2) }
    let(:mock_file) do
      instance_double(
        SimpleCov::SourceFile,
        filename: 'lib/dummy.rb',
        project_filename: 'lib/dummy.rb',
        covered_percent: 50.0,
        missed_lines: [mock_line]
      )
    end
    let(:mock_result) do
      instance_double(
        SimpleCov::Result,
        covered_percent: 90.0,
        covered_branches: 10,
        total_branches: 20,
        files: [mock_file]
      )
    end

    before do
      allow(mock_file).to receive(:respond_to?).with(:branches).and_return(false)
      allow(mock_file).to receive(:branches).and_return(nil)

      # Mock the AST resolver to avoid file system reads during basic format test
      node = SimpleCov::Formatter::AIFormatter::ASTResolver::SemanticNode.new(
        name: 'DummyClass', type: 'Class', start_line: 1, end_line: 10, bypasses: []
      )
      allow(SimpleCov::Formatter::AIFormatter::ASTResolver).to receive(:resolve).and_return([node])
    end

    it 'writes a markdown digest to the configured report tree' do
      formatter.format(mock_result)
      expect(File.exist?(config.report_path)).to be(true)

      content = File.read(config.report_path)
      expect(content).to include('# AI Coverage Digest')
      expect(content).to include('**Status:** FAILED')
      expect(content).to include('`lib/dummy.rb`')
      expect(content).to include('`DummyClass`')
    end

    it 'outputs to console when configured' do
      config.output_to_console = true
      expect { formatter.format(mock_result) }.to output(/\[SimpleCov AI Formatter\] Digest written/).to_stdout
    end

    it 'prevents dividing by zero when total_branches is nil' do
      allow(mock_result).to receive(:total_branches).and_return(nil)
      formatter.format(mock_result)
      expect(File.read(config.report_path)).to include('**Global Branch Coverage:** 0.0%')
    end

    context 'when 100% covered' do
      let(:mock_result_pass) do
        instance_double(SimpleCov::Result, covered_percent: 100.0, covered_branches: 20, total_branches: 20, files: [])
      end

      it 'reports PASSED' do
        formatter.format(mock_result_pass)
        content = File.read(config.report_path)
        expect(content).to include('**Status:** PASSED')
      end
    end

    context 'when handling branch coverage and truncation' do
      let(:mock_branch) { instance_double(SimpleCov::SourceFile::Branch, start_line: 5, end_line: 7) }

      before do
        allow(mock_file).to receive(:respond_to?).with(:branches).and_return(true)
        allow(mock_file).to receive(:branches).and_return(true)
        allow(mock_file).to receive(:missed_branches).and_return([mock_branch])
      end

      it 'reports branch deficits' do
        formatter.format(mock_result)
        content = File.read(config.report_path)
        expect(content).to include('**Branch Deficit:** Missing coverage for conditional.')
        expect(content).to include('`DummyClass`')
      end

      it 'reports unknown lines if AST node not found' do
        allow(mock_branch).to receive(:start_line).and_return(99)
        allow(mock_branch).to receive(:end_line).and_return(100)
        allow(mock_line).to receive(:line_number).and_return(99)
        formatter.format(mock_result)
        content = File.read(config.report_path)
        expect(content).to include('`Line 99`')
        expect(content).to include('`Lines 99-100`')
      end

      it 'truncates output if file size limit is reached' do
        config.max_file_size_kb = 0.0001
        formatter.format(mock_result)
        content = File.read(config.report_path)
        expect(content).to include('TRUNCATION NOTIFICATION')
      end
    end

    context 'when AST parser fails or file is corrupt' do
      it 'degrades gracefully' do
        allow(SimpleCov::Formatter::AIFormatter::ASTResolver).to receive(:resolve).and_raise(StandardError.new('Fatal parse'))
        formatter.format(mock_result)
        content = File.read(config.report_path)
        expect(content).to include('**ERROR:** AST Parsing Failed')
      end
    end

    context 'when tracking bypasses' do
      it 'reports files with :nocov: ignores' do
        node = SimpleCov::Formatter::AIFormatter::ASTResolver::SemanticNode.new(name: 'DummyClass', type: 'Class',
                                                                                start_line: 1, end_line: 10, bypasses: [':nocov:'])
        allow(SimpleCov::Formatter::AIFormatter::ASTResolver).to receive(:resolve).and_return([node])

        formatter.format(mock_result)
        content = File.read(config.report_path)
        expect(content).to include('Ignored Coverage Bypasses')
        expect(content).to include('Bypass Present:')
      end

      it 'does not report bypasses if disabled' do
        config.include_bypasses = false
        node = SimpleCov::Formatter::AIFormatter::ASTResolver::SemanticNode.new(name: 'DummyClass', type: 'Class',
                                                                                start_line: 1, end_line: 10, bypasses: [':nocov:'])
        allow(SimpleCov::Formatter::AIFormatter::ASTResolver).to receive(:resolve).and_return([node])

        formatter.format(mock_result)
        content = File.read(config.report_path)
        expect(content).not_to include('Ignored Coverage Bypasses')
      end
    end
  end

  describe SimpleCov::Formatter::AIFormatter::ASTResolver do
    let(:tmpdir) { Dir.mktmpdir }
    let(:ruby_file) { File.join(tmpdir, 'sample.rb') }
    let(:invalid_file) { File.join(tmpdir, 'invalid.rb') }

    after do
      FileUtils.remove_entry(tmpdir)
    end

    describe '.resolve' do
      it 'returns empty array for missing files' do
        expect(described_class.resolve('missing_file.rb')).to eq([])
      end

      it 'returns empty array for perfectly empty files gracefully' do
        File.write(ruby_file, '')
        expect(described_class.resolve(ruby_file)).to eq([])
      end

      it 'returns empty array gracefully for syntax errors' do
        File.write(invalid_file, "class Broken \n end def =")
        expect(described_class.resolve(invalid_file)).to eq([])
      end

      it 'resolves an AST structure accurately with modules and classes' do
        code = <<~RUBY
          module Analytics
            class Event
              # :nocov:
              def track
              end
              # :nocov:
          #{'    '}
              def self.name_event
              end
            end
          end
        RUBY
        File.write(ruby_file, code)

        nodes = described_class.resolve(ruby_file)

        # Module
        expect(nodes[0].name).to eq('Analytics')
        expect(nodes[0].type).to eq('Module')

        # Class nested inside Module
        expect(nodes[1].name).to eq('Analytics::Event')
        expect(nodes[1].type).to eq('Class')

        # Instance Method
        expect(nodes[2].name).to eq('Analytics::Event#track')
        expect(nodes[2].type).to eq('Instance Method')
        expect(nodes[2].bypasses).to include('# :nocov:')

        # Singleton Method
        expect(nodes[3].name).to eq('Analytics::Event.name_event')
        expect(nodes[3].type).to eq('Singleton Method')
      end

      it 'resolves root level methods correctly' do
        code = <<~RUBY
          def root_method
          end

          def self.root_class_method
          end
        RUBY
        File.write(ruby_file, code)

        nodes = described_class.resolve(ruby_file)
        expect(nodes[0].name).to eq('#root_method')
        expect(nodes[1].name).to eq('.root_class_method')
      end
    end
  end
end
