# typed: false
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SimpleCov::Formatter::AIFormatter::MarkdownBuilder::SnippetFormatter do
  subject(:harness) { Class.new { include SimpleCov::Formatter::AIFormatter::MarkdownBuilder::SnippetFormatter }.new }

  let(:node) do
    SimpleCov::Formatter::AIFormatter::ASTResolver::SemanticNode.new(
      name: 'Foo#bar', type: 'Instance Method', start_line: 1, end_line: 4
    )
  end
  let(:source_lines) { ["def bar\n", "  x = 1\n", "  x = 1\n", "end\n"] }

  def branch(start_line, end_line, type: :then)
    SimpleCov::SourceFile::Branch.new(start_line: start_line, end_line: end_line, coverage: 0, inline: true, type: type)
  end

  describe '#fetch_snippet_text' do
    it 'joins stripped non-empty lines' do
      expect(harness.fetch_snippet_text([1, 2], source_lines)).to eq('def bar x = 1')
    end

    it 'ignores non-positive line numbers instead of wrapping to the last line' do
      expect(harness.fetch_snippet_text([0], source_lines)).to eq('')
    end
  end

  describe '#truncate_snippet' do
    it 'appends an ellipsis when the character budget is exceeded' do
      expect(harness.truncate_snippet('a' * 100, 1)).to eq("#{'a' * 80}...")
    end

    it 'returns the text unchanged when within budget' do
      expect(harness.truncate_snippet('short', 5)).to eq('short')
    end
  end

  describe '#byte_slice' do
    it 'returns nil when the range exceeds the line' do
      expect(harness.byte_slice('abc', 0, 10)).to be_nil
    end

    it 'scrubs invalid byte sequences produced by slicing multibyte text' do
      # 'é' is two UTF-8 bytes; slicing one of them yields an invalid sequence that is scrubbed.
      expect(harness.byte_slice('é', 0, 1)).not_to be_nil
    end
  end

  describe '#calculate_occurrence' do
    it 'returns an empty string when there is no node' do
      expect(harness.calculate_occurrence(2, source_lines, nil)).to eq('')
    end

    it 'returns an empty string when the target line is blank' do
      expect(harness.calculate_occurrence(5, source_lines, node)).to eq('')
    end

    it 'labels duplicate occurrences within the node' do
      expect(harness.calculate_occurrence(3, source_lines, node)).to eq('(Occurrence 2 of 2).')
    end

    it 'skips blank lines inside the node when counting occurrences' do
      spaced_node = SimpleCov::Formatter::AIFormatter::ASTResolver::SemanticNode.new(
        name: 'Foo#spaced', type: 'Instance Method', start_line: 1, end_line: 5
      )
      spaced_lines = ["def spaced\n", "  x = 1\n", "\n", "  x = 1\n", "end\n"]
      expect(harness.calculate_occurrence(4, spaced_lines, spaced_node)).to eq('(Occurrence 2 of 2).')
    end

    it 'returns an empty string for a unique snippet' do
      expect(harness.calculate_occurrence(1, source_lines, node)).to eq('')
    end

    it 'tolerates a node that extends past the end of the source' do
      expect(harness.calculate_occurrence(2, source_lines.first(2), node)).to eq('')
    end
  end

  describe '#extract_branch_text' do
    it 'falls back to the full line range when column data is absent' do
      expect(harness.extract_branch_text(branch(2, 2), source_lines, nil)).to eq('x = 1')
    end

    it 'uses the inline slice when column data is present' do
      expect(harness.extract_branch_text(branch(2, 2), source_lines, [2, 3])).to eq('x')
    end

    it 'joins the lines of a multi-line branch even when column data is present' do
      expect(harness.extract_branch_text(branch(1, 2), source_lines, [0, 3])).to eq('def bar x = 1')
    end
  end

  describe '#extract_inline_branch' do
    it 'returns nil when the branch line is beyond the source' do
      expect(harness.extract_inline_branch(branch(99, 99), [0, 2], source_lines)).to be_nil
    end

    it 'returns nil when the column range exceeds the line length' do
      expect(harness.extract_inline_branch(branch(2, 2), [0, 999], source_lines)).to be_nil
    end
  end
end
