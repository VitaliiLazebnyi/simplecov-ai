# typed: false
# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'

# Regions come from SimpleCov's own skip verdicts, so `# simplecov:disable` scenarios expect a
# region on SimpleCov >= 1.0 (which implements the directive) and none on older releases. A
# skipped region made only of comments and blank lines excludes nothing and is never a region.
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

  it 'drops a nocov pair that wraps only comments and blank lines, which excludes nothing' do
    source = "class A\n  #{nocov_marker}\n  # a note\n\n  #{nocov_marker}\n  def a\n  end\nend\n"
    expect(regions_of(source)).to eq([])
  end

  it 'keeps a nocov pair that wraps a comment and a statement' do
    source = "class A\n  #{nocov_marker}\n  # a note\n  def a\n  end\n  #{nocov_marker}\nend\n"
    expect(regions_of(source)).to eq([[2..6, nocov_marker]])
  end

  it 'keeps only the regions holding a relevant line when a comment-only region sits beside them' do
    source = "#{nocov_marker}\n# one\n#{nocov_marker}\nB = 2\n#{nocov_marker}\nA = 1\n#{nocov_marker}\n"
    expect(regions_of(source)).to eq([[5..7, nocov_marker]])
  end

  # SimpleCov >= 1.0 honours a directive wherever it appears in a comment, so a comment quoting
  # one is an inline directive that skips its own line — a comment, hence no bypass.
  it 'reports no region for a comment that merely mentions a directive, although SimpleCov skips it' do
    file = file_for("def a\n  # see `# simplecov:disable` in the README\n  1\nend\n")
    skipped = file.skipped_lines.map(&:line_number)
    expect([skipped, described_class.of(file, file.src)]).to eq([when_directives_supported([2]), []])
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

  it 'lists a branch-only region before a later line region, in source order' do
    source = "def a(flag)\n  # simplecov:disable branch\n  flag ? 1 : 2\n  # simplecov:enable branch\n  " \
             "#{nocov_marker}\n  3\n  #{nocov_marker}\nend\n"
    branches = { branch_descriptor(source, :if, 0, 3, 'flag ? 1 : 2') => {
      branch_descriptor(source, :then, 1, 3, '1') => 1, branch_descriptor(source, :else, 2, 3, '2') => 0
    } }
    skip 'branch directives need SimpleCov >= 1.0' unless simplecov_directives_supported?
    expect(regions_of(source, branches: branches)).to eq([[3..3, '# simplecov:disable branch'], [5..7, nocov_marker]])
  end

  it 'honours the nocov token SimpleCov is configured with when reading reasons, escaping it' do
    # SimpleCov compiles its marker pattern once per process, so the file's skip verdicts are
    # settled before the token reader is stubbed for the reason lookup; the token carries a
    # regexp metacharacter to show it is matched literally.
    file = file_for("def a\n  #{nocov_marker}\n  1\n  #{nocov_marker}\nend\n")
    file.skipped_lines
    token_reader = SimpleCov.respond_to?(:current_nocov_token) ? :current_nocov_token : :nocov_token
    allow(SimpleCov).to receive(token_reader).and_return('c+v')
    expect(described_class.of(file, file.src.map { |line| line.sub('nocov', 'c+v') })).to eq([[2..4, '# :c+v:']])
  end

  it 'quotes the directive without the whitespace that trails it' do
    file = file_for("def a\n  #{nocov_marker}\n  1\n  #{nocov_marker}\nend\n")
    expect(described_class.of(file, file.src.map { |line| line.sub("\n", "   \n") })).to eq([[2..4, nocov_marker]])
  end

  it 'reads the token through nocov_token on a SimpleCov without current_nocov_token (< 1.0)' do
    file = file_for("def a\n  #{nocov_marker}\n  1\n  #{nocov_marker}\nend\n")
    # SimpleCov's own skip verdicts are settled before its token reader is taken away.
    file.skipped_lines
    without_method(SimpleCov, :current_nocov_token)
    allow(SimpleCov).to receive(:nocov_token).and_return('nocov')
    expect(described_class.of(file, file.src)).to eq([[2..4, nocov_marker]])
  end

  it 'reads the token without triggering the deprecation of nocov_token on SimpleCov >= 1.0' do
    file = file_for("def a\n  #{nocov_marker}\n  1\n  #{nocov_marker}\nend\n")
    # SimpleCov warns once per call site; forgetting earlier warnings makes this call decisive.
    SimpleCov::Deprecation.emitted.clear if defined?(SimpleCov::Deprecation)
    expect { described_class.of(file, file.src) }.not_to output.to_stderr
  end

  it 'falls back to a generic reason when the source is unavailable' do
    source = "def a\n  #{nocov_marker}\n  1\n  #{nocov_marker}\nend\n"
    expect(described_class.of(file_for(source), [])).to eq([[2..4, 'coverage skipped by SimpleCov']])
  end

  it 'falls back to a generic reason when no directive sits on or above the region' do
    source = "def a\n  #{nocov_marker}\n  1\n  #{nocov_marker}\nend\n"
    regions = described_class.of(file_for(source), ["def a\n", "  1\n", "  2\n", "  3\n", "end #{nocov_marker}\n"])
    expect(regions).to eq([[2..4, 'coverage skipped by SimpleCov']])
  end

  describe '.any?' do
    it 'is true when SimpleCov skipped a line' do
      expect(described_class.any?(file_for("#{nocov_marker}\nA = 1\n#{nocov_marker}\n"))).to be(true)
    end

    it 'is true when SimpleCov skipped only a branch' do
      source = "def a(flag)\n  # simplecov:disable branch\n  flag ? 1 : 2\n  # simplecov:enable branch\nend\n"
      branches = { branch_descriptor(source, :if, 0, 3, 'flag ? 1 : 2') => {
        branch_descriptor(source, :then, 1, 3, '1') => 1, branch_descriptor(source, :else, 2, 3, '2') => 0
      } }
      skip 'branch directives need SimpleCov >= 1.0' unless simplecov_directives_supported?
      expect(described_class.any?(file_for(source, branches: branches))).to be(true)
    end

    it 'is false for a file with branches none of which is skipped' do
      source = "def a(flag)\n  flag ? 1 : 2\nend\n"
      branches = { branch_descriptor(source, :if, 0, 2, 'flag ? 1 : 2') => {
        branch_descriptor(source, :then, 1, 2, '1') => 1, branch_descriptor(source, :else, 2, 2, '2') => 0
      } }
      expect(described_class.any?(file_for(source, branches: branches))).to be(false)
    end

    it 'is false for a file SimpleCov skipped nothing in' do
      expect(described_class.any?(file_for("A = 1\n"))).to be(false)
    end
  end
end
