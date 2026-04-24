# typed: false
# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'stringio'
require 'tmpdir'

RSpec.describe SimpleCov::Formatter::AIFormatter do
  extend T::Sig

  let(:config) { described_class.configuration }

  sig { returns(String) }
  def read_report
    File.read(config.report_path)
  end

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
        missed_lines: [mock_line, instance_double(SimpleCov::SourceFile::Line, line_number: 3)],
        missed_branches: []
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
        name: 'DummyClass', type: 'Class', start_line: 1, end_line: 10, bypass_reasons: []
      )
      child_node = SimpleCov::Formatter::AIFormatter::ASTResolver::SemanticNode.new(
        name: 'DummyClass#initialize', type: 'Instance Method', start_line: 2, end_line: 4, bypass_reasons: []
      )
      allow(SimpleCov::Formatter::AIFormatter::ASTResolver).to receive(:resolve).and_return([node, child_node])

      # Mock file reading to simulate reading source lines for snippets
      allow(File).to receive(:readlines).with('lib/dummy.rb').and_return([
                                                                           "class DummyClass\n",
                                                                           "  def initialize\n",
                                                                           "    @foo = 1\n",
                                                                           "  end\n",
                                                                           "  def branch_test\n",
                                                                           "    break if stream.closed?\n",
                                                                           "  end\n",
                                                                           "  def branch_test_2\n",
                                                                           "    break if stream.closed?\n",
                                                                           "  end\n"
                                                                         ])
    end

    context 'when writing a basic digest' do
      let(:mock_result) do
        instance_double(
          SimpleCov::Result,
          covered_percent: 90.0,
          covered_branches: 10,
          total_branches: 20,
          files: [mock_file]
        )
      end

      before { formatter.format(mock_result) }

      it('creates the report file') { expect(File.exist?(config.report_path)).to be(true) }
      it('includes the main title') { expect(read_report).to include('# AI Coverage Digest') }
      it('includes the overall status') { expect(read_report).to include('**Status:** FAILED') }
      it('includes the targeted filename') { expect(read_report).to include('`lib/dummy.rb`') }
      it('includes the semantic method name') { expect(read_report).to include('`DummyClass#initialize`') }
      it('includes the correct branch coverage') { expect(read_report).to include('**Global Branch Coverage:** 50.0%') }

      it('includes the formatted generated at timestamp') do
        regex = /\*\*Generated At:\*\* \d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(Z|[+-]\d{2}:\d{2}) \(Local Timezone\)/
        expect(read_report).to match(regex)
      end
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
      let(:content) { File.read(config.report_path) }

      before { formatter.format(mock_result_pass) }

      it('reports PASSED status') { expect(content).to include('**Status:** PASSED') }
      it('omits Coverage Deficits section') { expect(content).not_to include('## Coverage Deficits') }
    end

    context 'when handling branch coverage and truncation' do
      let(:mock_branch) { instance_double(SimpleCov::SourceFile::Branch, start_line: 5, end_line: 7) }

      before do
        allow(mock_file).to receive(:respond_to?).with(:branches).and_return(true)
        allow(mock_file).to receive_messages(branches: [mock_branch], missed_branches: [mock_branch])
      end

      context 'when formatting branch deficits' do
        before { formatter.format(mock_result) }

        let(:content) { File.read(config.report_path) }

        it('reports missing branch coverage text') {
          expect(content).to include('**Branch Deficit:** Missing coverage')
        }

        it('includes the class name') { expect(content).to include('`DummyClass`') }
        it('includes the innermost method name for lines') { expect(content).to include('`DummyClass#initialize`') }
        it('reports exact line 2 snippet') { expect(content).to include('`def initialize`') }
        it('reports exact line 3 snippet') { expect(content).to include('`@foo = 1`') }
        it('groups semantic node headers uniquely') { expect(content.scan('- `DummyClass#initialize`').size).to eq(1) }
        it('groups line deficits together') { expect(content.scan('- **Line Deficit:**').size).to eq(2) }

        it('sorts the output chronologically') do
          expect(content).to match(/`DummyClass`.*Branch Deficit.*`DummyClass#initialize`.*`def initialize`/m)
        end
      end

      context 'with coarse granularity' do
        before do
          config.granularity = :coarse
          formatter.format(mock_result)
        end

        it('includes summary text') { expect(read_report).to include('Contains unexecuted lines or branches.') }
        it('omits specific code snippets') { expect(read_report).not_to include('`def initialize`') }
      end

      context 'when truncating extremely long snippets using max_snippet_lines' do
        before do
          long_line = "  def initialize #{'A' * 100}\n"
          allow(File).to receive(:readlines).with('lib/dummy.rb').and_return(["class DummyClass\n", long_line,
                                                                              "  end\n"])
          config.max_snippet_lines = 1
          formatter.format(mock_result)
        end

        let(:content) { File.read(config.report_path) }

        it('includes the truncated prefix') { expect(content).to include('A' * 50) }
        it('includes the trailing ellipsis') { expect(content).to include('...') }
        it('does not include the full string') { expect(content).not_to include('A' * 100) }
      end

      context 'with identical snippets' do
        before do
          allow(mock_line).to receive(:line_number).and_return(9)
          formatter.format(mock_result)
        end

        it('labels the duplicate occurrence') { expect(read_report).to include('(Occurrence 2 of 2)') }
        it('includes the snippet text') { expect(read_report).to include('break if stream.closed?') }
      end

      context 'with missing AST nodes' do
        before do
          allow(mock_branch).to receive_messages(start_line: 99, end_line: 100)
          allow(mock_line).to receive(:line_number).and_return(99)
          formatter.format(mock_result)
        end

        it('reports generic Line number') { expect(read_report).to include('`Line 99`') }
        it('reports generic Lines range') { expect(read_report).to include('`Lines 99-100`') }
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
        allow(SimpleCov::Formatter::AIFormatter::ASTResolver).to receive(:resolve)
                                                             .and_raise(StandardError.new('Fatal parse'))
        formatter.format(mock_result)
        content = File.read(config.report_path)
        expect(content).to include('**ERROR:** AST Parsing Failed')
      end
    end

    context 'when evaluating AST performance' do
      it 'caches the resolved AST preventing redundant file system reads' do
        # Clear the allow from the before block for this specific test
        allow(SimpleCov::Formatter::AIFormatter::ASTResolver).to receive(:resolve).and_call_original

        node = SimpleCov::Formatter::AIFormatter::ASTResolver::SemanticNode.new(
          name: 'DummyClass', type: 'Class', start_line: 1, end_line: 10, bypass_reasons: [':nocov:']
        )
        allow(SimpleCov::Formatter::AIFormatter::ASTResolver).to receive(:resolve)
                                                             .with('lib/dummy.rb')
          .and_return([node])

        config.include_bypasses = true
        formatter.format(mock_result)

        expect(SimpleCov::Formatter::AIFormatter::ASTResolver).to have_received(:resolve).with('lib/dummy.rb').once
      end
    end

    context 'when tracking bypasses' do
      before do
        node = SimpleCov::Formatter::AIFormatter::ASTResolver::SemanticNode.new(name: 'DummyClass', type: 'Class',
                                                                                start_line: 1,
                                                                                end_line: 10,
                                                                                bypass_reasons: [':nocov:'])
        allow(SimpleCov::Formatter::AIFormatter::ASTResolver).to receive(:resolve).and_return([node])
        formatter.format(mock_result)
      end

      it('includes the bypass section') { expect(read_report).to include('Ignored Coverage Bypasses') }

      it('includes the bypass reason') {
        regex = /\*\*Bypass Present:\*\* Contains `:nocov:` directive /
        expect(read_report).to match(regex)
      }
    end

    context 'when tracking bypasses with disabled config' do
      before do
        config.include_bypasses = false
        node = SimpleCov::Formatter::AIFormatter::ASTResolver::SemanticNode.new(name: 'DummyClass', type: 'Class',
                                                                                start_line: 1,
                                                                                end_line: 10,
                                                                                bypass_reasons: [':nocov:'])
        allow(SimpleCov::Formatter::AIFormatter::ASTResolver).to receive(:resolve).and_return([node])
        formatter.format(mock_result)
      end

      it('does not report bypasses if disabled') { expect(read_report).not_to include('Ignored Coverage Bypasses') }
    end
  end

  describe 'ASTResolver' do
    let(:tmpdir) { Dir.mktmpdir }
    let(:ruby_file) { File.join(tmpdir, 'sample.rb') }
    let(:invalid_file) { File.join(tmpdir, 'invalid.rb') }

    after do
      FileUtils.remove_entry(tmpdir)
    end

    describe '.resolve' do
      it 'returns empty array for missing files' do
        expect(SimpleCov::Formatter::AIFormatter::ASTResolver.resolve('missing_file.rb')).to eq([])
      end

      it 'returns empty array for perfectly empty files gracefully' do
        File.write(ruby_file, '')
        expect(SimpleCov::Formatter::AIFormatter::ASTResolver.resolve(ruby_file)).to eq([])
      end

      it 'raises error gracefully for syntax errors' do
        File.write(invalid_file, "class Broken \n end def =")
        expect { SimpleCov::Formatter::AIFormatter::ASTResolver.resolve(invalid_file) }.to raise_error(Parser::SyntaxError)
      end

      context 'when resolving an AST structure accurately with modules and classes and handles :nocov: variations' do
        let(:code) do
          <<~RUBY
            module Analytics
              class Event
                # Justification: Mock string for testing
                # :nocov:
                def track
                end
                # Justification: Mock string for testing
                #    :nocov:#{'  '}
                def track_spaced
                end
                # Justification: Mock string for testing
                # rubocop:disable Metrics/MethodLength, :nocov:
                def self.name_event
                end
              end
            end
          RUBY
        end
        let(:nodes) { SimpleCov::Formatter::AIFormatter::ASTResolver.resolve(ruby_file) }

        before { File.write(ruby_file, code) }

        it('resolves Module') { expect(nodes[0].name).to eq('Analytics') }
        it('resolves Module type') { expect(nodes[0].type).to eq('Module') }
        it('resolves Class name') { expect(nodes[1].name).to eq('Analytics::Event') }
        it('resolves Class type') { expect(nodes[1].type).to eq('Class') }

        it('resolves Class bypasses as empty because they belong to children') do
          expect(nodes[1].bypass_reasons).to be_empty
        end

        it('resolves Instance Method 1 name') { expect(nodes[2].name).to eq('Analytics::Event#track') }
        it('resolves Instance Method 1 type') { expect(nodes[2].type).to eq('Instance Method') }
        it('resolves Instance Method 1 bypass') { expect(nodes[2].bypass_reasons).to include('# :nocov:') }
        it('resolves Instance Method 2 name') { expect(nodes[3].name).to eq('Analytics::Event#track_spaced') }
        it('resolves Instance Method 2 type') { expect(nodes[3].type).to eq('Instance Method') }
        it('resolves Instance Method 2 bypass') { expect(nodes[3].bypass_reasons).to include('#    :nocov:') }
        it('resolves Singleton Method name') { expect(nodes[4].name).to eq('Analytics::Event.name_event') }
        it('resolves Singleton Method type') { expect(nodes[4].type).to eq('Singleton Method') }

        it('resolves Singleton Method bypass') {
          expect(nodes[4].bypass_reasons).to include('# rubocop:disable Metrics/MethodLength, :nocov:')
        }
      end

      context 'when resolving root level methods correctly' do
        let(:code) do
          <<~RUBY
            def root_method
            end

            def self.root_class_method
            end
          RUBY
        end
        let(:nodes) { SimpleCov::Formatter::AIFormatter::ASTResolver.resolve(ruby_file) }

        before { File.write(ruby_file, code) }

        it('resolves root instance method') { expect(nodes[0].name).to eq('#root_method') }
        it('resolves root class method') { expect(nodes[1].name).to eq('.root_class_method') }
      end
    end
  end
end
