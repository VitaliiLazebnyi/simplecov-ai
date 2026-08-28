# typed: false
# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'

# Regions come from SimpleCov's own skip verdicts, so `# simplecov:disable` scenarios expect a
# region on SimpleCov >= 1.0 (which implements the directive) and none on older releases.
RSpec.describe SimpleCov::Formatter::AIFormatter::MarkdownBuilder::SkipRegions do
  let(:tmpdir) { Dir.mktmpdir('scai') }

  after { FileUtils.remove_entry(tmpdir) }

  def file_for(source, branches: {})
    path = write_source(tmpdir, "skip#{source.hash.abs}.rb", source)
    source_file(path, { 'lines' => Array.new(source.lines.size, 1), 'branches' => branches })
  end

  def regions_of(source, branches: {})
    file = file_for(source, branches: branches)
    described_class.of(file, file.src)
  end

  def when_directives_supported(regions)
    simplecov_directives_supported? ? regions : []
  end

  it 'turns a nocov pair into one region carrying the marker text, marker lines included' do
    source = "class A\n  #{nocov_marker}\n  def a\n  end\n  #{nocov_marker}\n  def b\n  end\nend\n"
    expect(regions_of(source)).to eq([[2..5, nocov_marker]])
  end

  it 'extends an unmatched nocov marker to the end of the file' do
    source = "class A\n  #{nocov_marker}\n  def a\n  end\nend\n"
    expect(regions_of(source)).to eq([[2..5, nocov_marker]])
  end

  it 'keeps separate regions for separate nocov pairs' do
    source = "#{nocov_marker}\nA = 1\n#{nocov_marker}\nB = 2\n#{nocov_marker}\nC = 3\n#{nocov_marker}\n"
    expect(regions_of(source)).to eq([[1..3, nocov_marker], [5..7, nocov_marker]])
  end

  it 'reports a simplecov:disable block with its full comment as the reason' do
    source = <<~RUBY
      class A
        # simplecov:disable line not worth testing
        def a
        end
        # simplecov:enable line
        def b
        end
      end
    RUBY
    expected = [[2..5, '# simplecov:disable line not worth testing']]
    expect(regions_of(source)).to eq(when_directives_supported(expected))
  end

  it 'reports an inline simplecov:disable as a one-line region with the trailing comment' do
    source = "def a\n  raise 'x' # simplecov:disable\nend\n"
    expect(regions_of(source)).to eq(when_directives_supported([[2..2, '# simplecov:disable']]))
  end

  it 'ignores a directive inside a heredoc, exactly as SimpleCov does' do
    source = "def a\n  <<~TEXT\n    # simplecov:disable\n  TEXT\nend\n"
    expect(regions_of(source)).to eq([])
  end

  it 'derives a branch-only region from the skipped arms and finds the directive above them' do
    source = "def a(flag)\n  # simplecov:disable branch\n  flag ? 1 : 2\n  # simplecov:enable branch\nend\n"
    branches = { branch_descriptor(source, :if, 0, 3, 'flag ? 1 : 2') => {
      branch_descriptor(source, :then, 1, 3, '1') => 1, branch_descriptor(source, :else, 2, 3, '2') => 0
    } }
    expected = [[3..3, '# simplecov:disable branch']]
    expect(regions_of(source, branches: branches)).to eq(when_directives_supported(expected))
  end

  it 'finds a trailing branch directive on the condition line for the arm SimpleCov skips by its report line' do
    source = "def a(flag)\n  if flag # simplecov:disable branch\n    :yes\n  else\n    :no\n  end\nend\n"
    branches = { multiline_branch_descriptor(:if, 0, 2, 6) => {
      multiline_branch_descriptor(:then, 1, 3, 3) => 1, multiline_branch_descriptor(:else, 2, 5, 5) => 0
    } }
    # SimpleCov reports the `then` arm on the `if` line (skipped) and the `else` arm on the
    # `else` line (not skipped), so exactly one region results.
    expected = [[3..3, '# simplecov:disable branch']]
    expect(regions_of(source, branches: branches)).to eq(when_directives_supported(expected))
  end

  it 'drops branch ranges already covered by a skipped line region' do
    source = "def a(flag)\n  #{nocov_marker}\n  flag ? 1 : 2\n  #{nocov_marker}\nend\n"
    branches = { branch_descriptor(source, :if, 0, 3, 'flag ? 1 : 2') => {
      branch_descriptor(source, :then, 1, 3, '1') => 0, branch_descriptor(source, :else, 2, 3, '2') => 0
    } }
    expect(regions_of(source, branches: branches)).to eq([[2..4, nocov_marker]])
  end

  it 'honours the nocov token SimpleCov is configured with when reading reasons' do
    # SimpleCov compiles its marker pattern once per process, so the file's skip verdicts are
    # settled before the token reader is stubbed for the reason lookup.
    file = file_for("def a\n  #{nocov_marker}\n  1\n  #{nocov_marker}\nend\n")
    file.skipped_lines
    token_reader = SimpleCov.respond_to?(:current_nocov_token) ? :current_nocov_token : :nocov_token
    allow(SimpleCov).to receive(token_reader).and_return('skipme')
    expect(described_class.of(file, file.src.map { |line| line.sub('nocov', 'skipme') })).to eq([[2..4, '# :skipme:']])
  end

  it 'falls back to a generic reason when the directive cannot be located in the source' do
    source = "def a\n  #{nocov_marker}\n  1\n  #{nocov_marker}\nend\n"
    expect(described_class.of(file_for(source), [])).to eq([[2..4, 'coverage skipped by SimpleCov']])
  end

  describe '.any?' do
    it 'is true when SimpleCov skipped a line' do
      expect(described_class.any?(file_for("#{nocov_marker}\nA = 1\n#{nocov_marker}\n"))).to be(true)
    end

    it 'is false for a file SimpleCov skipped nothing in' do
      expect(described_class.any?(file_for("A = 1\n"))).to be(false)
    end
  end
end
