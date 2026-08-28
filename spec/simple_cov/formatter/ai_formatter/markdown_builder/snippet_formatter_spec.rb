# typed: false
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SimpleCov::Formatter::AIFormatter::MarkdownBuilder::SnippetFormatter do
  subject(:harness) { Class.new { include SimpleCov::Formatter::AIFormatter::MarkdownBuilder::SnippetFormatter }.new }

  let(:node) { semantic_node('Foo#bar', 1, 4) }
  let(:source_lines) { ["def bar\n", "  x = 1\n", "  x = 1\n", "end\n"] }

  def semantic_node(name, start_line, end_line)
    SimpleCov::Formatter::AIFormatter::ASTResolver::SemanticNode.new(
      name: name, type: 'Instance Method', start_line: start_line, end_line: end_line
    )
  end

  def branch(start_line, end_line, type: :then)
    SimpleCov::SourceFile::Branch.new(start_line: start_line, end_line: end_line, coverage: 0, inline: true, type: type)
  end

  describe '#fetch_snippet_text' do
    it 'joins stripped non-empty lines' do
      expect(harness.fetch_snippet_text([1, 2], source_lines)).to eq('def bar x = 1')
    end

    it 'leaves blank lines inside the range out of the join' do
      expect(harness.fetch_snippet_text([1, 2, 3], ["def a\n", "\n", "end\n"])).to eq('def a end')
    end

    it 'ignores non-positive line numbers instead of wrapping to the last line' do
      expect(harness.fetch_snippet_text([0, -1], source_lines)).to eq('')
    end

    it 'ignores line numbers beyond the end of the source' do
      expect(harness.fetch_snippet_text([1, 99], source_lines)).to eq('def bar')
    end
  end

  describe '#truncate_snippet' do
    it 'keeps the first 80 characters per allowed line and appends an ellipsis' do
      digits = (1..200).map { |number| number % 10 }.join
      one_line = harness.truncate_snippet(digits, 1)
      two_lines = harness.truncate_snippet(digits, 2)
      expect([one_line, two_lines]).to eq(["#{digits[0, 80]}...", "#{digits[0, 160]}..."])
    end

    it 'returns text within the budget unchanged' do
      expect(harness.truncate_snippet('a' * 80, 1)).to eq('a' * 80)
    end
  end

  describe '#byte_slice' do
    it 'slices by byte offsets, up to and including the last byte of the line' do
      expect([harness.byte_slice('abc', 1, 3), harness.byte_slice('abc', 0, 3)]).to eq(%w[bc abc])
    end

    it 'returns nil when the range exceeds the line' do
      expect(harness.byte_slice('abc', 0, 4)).to be_nil
    end

    it 'returns an empty string for a start beyond the line or an inverted range' do
      expect([harness.byte_slice('abc', 4, 1), harness.byte_slice('abc', 3, 1)]).to eq(['', ''])
    end

    it 'restores the encoding of a slice taken on multibyte text' do
      # 'é' is two UTF-8 bytes; both bytes give the character back, in the line's encoding.
      slice = harness.byte_slice('aé', 1, 3)
      expect([slice, slice.encoding]).to eq(['é', Encoding::UTF_8])
    end

    it 'scrubs a slice that cuts a multibyte character' do
      expect(harness.byte_slice('é', 0, 1)).to eq('�')
    end
  end

  describe '#calculate_occurrence' do
    it 'returns an empty string when there is no node' do
      expect(harness.calculate_occurrence(2, source_lines, nil)).to eq('')
    end

    it 'returns an empty string for a line beyond the source' do
      expect(harness.calculate_occurrence(5, source_lines, node)).to eq('')
    end

    it 'returns an empty string for a blank line, however many blank lines the node has' do
      expect(harness.calculate_occurrence(3, "a\n\n\n".lines, semantic_node('Foo#b', 1, 3))).to eq('')
    end

    it 'numbers duplicate occurrences within the node by position' do
      first = harness.calculate_occurrence(2, source_lines, node)
      second = harness.calculate_occurrence(3, source_lines, node)
      expect([first, second]).to eq(['(Occurrence 1 of 2).', '(Occurrence 2 of 2).'])
    end

    it 'counts a duplicate on the last line of the node' do
      last_line_node = semantic_node('Foo#bar', 2, 3)
      expect(harness.calculate_occurrence(3, source_lines, last_line_node)).to eq('(Occurrence 2 of 2).')
    end

    it 'counts only the lines of the node' do
      expect(harness.calculate_occurrence(2, source_lines, semantic_node('Foo#bar', 1, 2))).to eq('')
    end

    it 'skips blank lines inside the node when counting occurrences' do
      spaced_lines = ["def spaced\n", "  x = 1\n", "\n", "  x = 1\n", "end\n"]
      spaced_node = semantic_node('Foo#spaced', 1, 5)
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
    it 'returns the byte slice of the branch line, stripped on both sides' do
      lines = ["def bar\n", "  x = 1\n", "  y = 2\n", "end\n"]
      exact = harness.extract_inline_branch(branch(2, 2), [2, 3], lines)
      padded = harness.extract_inline_branch(branch(3, 3), [1, 6], lines)
      expect([exact, padded]).to eq(['x', 'y ='])
    end

    it 'returns nil for a multi-line branch, whatever the columns' do
      expect(harness.extract_inline_branch(branch(1, 2), [0, 3], source_lines)).to be_nil
    end

    it 'returns nil without column data' do
      expect(harness.extract_inline_branch(branch(2, 2), nil, source_lines)).to be_nil
    end

    it 'returns nil when the branch line is beyond the source' do
      expect(harness.extract_inline_branch(branch(99, 99), [0, 2], source_lines)).to be_nil
    end

    it 'returns nil when the column range exceeds the line length' do
      expect(harness.extract_inline_branch(branch(2, 2), [0, 999], source_lines)).to be_nil
    end
  end

  describe '#first_source_line' do
    it 'returns the first non-blank line of the branch, stripped' do
      lines = ["\n", "  elsif number.odd?\n", "  :odd\n"]
      expect(harness.first_source_line(branch(1, 3), lines)).to eq('elsif number.odd?')
    end

    it 'finds text on the last line of the branch' do
      expect(harness.first_source_line(branch(1, 2), "\nlate\n".lines)).to eq('late')
    end

    it 'looks no further than the last line of the branch' do
      expect(harness.first_source_line(branch(1, 1), "\nlate\n".lines)).to eq('')
    end

    it 'returns an empty string when the range is blank or beyond the source' do
      blank = harness.first_source_line(branch(1, 2), ["\n", "  \n"])
      beyond = harness.first_source_line(branch(5, 6), source_lines)
      expect([blank, beyond]).to eq(['', ''])
    end
  end

  describe '#line_label' do
    it 'labels a single line by its number and a span by its bounds, as strings' do
      expect([harness.line_label(12, 12), harness.line_label(12, 15)]).to eq(%w[12 12-15])
    end
  end
end
