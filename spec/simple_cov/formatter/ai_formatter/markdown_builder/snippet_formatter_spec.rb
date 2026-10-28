# typed: false
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SimpleCov::Formatter::AIFormatter::MarkdownBuilder::SnippetFormatter do
  subject(:snippets) { described_class.new(source_lines, 1) }

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

  def snippets_of(lines, max_snippet_lines = 1)
    described_class.new(lines, max_snippet_lines)
  end

  describe '#text' do
    it 'joins stripped non-empty lines' do
      expect(snippets.text([1, 2])).to eq('def bar x = 1')
    end

    it 'leaves blank lines inside the range out of the join' do
      expect(snippets_of(["def a\n", "\n", "end\n"]).text(1..3)).to eq('def a end')
    end

    it 'ignores non-positive line numbers instead of wrapping to the last line' do
      expect(snippets.text([0, -1])).to eq('')
    end

    it 'ignores line numbers beyond the end of the source' do
      expect(snippets.text([1, 99])).to eq('def bar')
    end
  end

  describe '#truncate' do
    it 'keeps the first 80 characters per allowed line and appends an ellipsis' do
      digits = (1..200).map { |number| number % 10 }.join
      one_line = snippets_of([], 1).truncate(digits)
      two_lines = snippets_of([], 2).truncate(digits)
      expect([one_line, two_lines]).to eq(["#{digits[0, 80]}...", "#{digits[0, 160]}..."])
    end

    it 'returns text within the budget unchanged' do
      expect(snippets.truncate('a' * 80)).to eq('a' * 80)
    end
  end

  describe '.byte_slice' do
    it 'slices by byte offsets, up to and including the last byte of the line' do
      expect([described_class.byte_slice('abc', 1, 3), described_class.byte_slice('abc', 0, 3)]).to eq(%w[bc abc])
    end

    it 'returns nil when the range exceeds the line' do
      expect(described_class.byte_slice('abc', 0, 4)).to be_nil
    end

    it 'returns an empty string for a start beyond the line or an inverted range' do
      expect([described_class.byte_slice('abc', 4, 1), described_class.byte_slice('abc', 3, 1)]).to eq(['', ''])
    end

    it 'restores the encoding of a slice taken on multibyte text' do
      # 'é' is two UTF-8 bytes; both bytes give the character back, in the line's encoding.
      slice = described_class.byte_slice('aé', 1, 3)
      expect([slice, slice.encoding]).to eq(['é', Encoding::UTF_8])
    end

    it 'scrubs a slice that cuts a multibyte character' do
      expect(described_class.byte_slice('é', 0, 1)).to eq('�')
    end

    it 'strips the slice on both sides' do
      expect(described_class.byte_slice('  y = 2  ', 1, 8)).to eq('y = 2')
    end
  end

  describe '#occurrence' do
    it 'returns an empty string when there is no node' do
      expect(snippets.occurrence(2, nil)).to eq('')
    end

    it 'returns an empty string for a line beyond the source' do
      expect(snippets.occurrence(5, node)).to eq('')
    end

    it 'returns an empty string for a blank line, however many blank lines the node has' do
      expect(snippets_of("a\n\n\n".lines).occurrence(3, semantic_node('Foo#b', 1, 3))).to eq('')
    end

    it 'numbers duplicate occurrences within the node by position' do
      expect([snippets.occurrence(2, node), snippets.occurrence(3, node)])
        .to eq(['(Occurrence 1 of 2).', '(Occurrence 2 of 2).'])
    end

    it 'counts a duplicate on the last line of the node' do
      expect(snippets.occurrence(3, semantic_node('Foo#bar', 2, 3))).to eq('(Occurrence 2 of 2).')
    end

    it 'counts only the lines of the node' do
      expect(snippets.occurrence(2, semantic_node('Foo#bar', 1, 2))).to eq('')
    end

    it 'skips blank lines inside the node when counting occurrences' do
      spaced = snippets_of(["def spaced\n", "  x = 1\n", "\n", "  x = 1\n", "end\n"])
      expect(spaced.occurrence(4, semantic_node('Foo#spaced', 1, 5))).to eq('(Occurrence 2 of 2).')
    end

    it 'returns an empty string for a unique snippet' do
      expect(snippets.occurrence(1, node)).to eq('')
    end

    it 'tolerates a node that extends past the end of the source' do
      expect(snippets_of(source_lines.first(2)).occurrence(2, node)).to eq('')
    end

    it 'labels nothing for a line outside the node, whatever its text' do
      expect(snippets.occurrence(4, semantic_node('Foo#bar', 1, 2))).to eq('')
    end

    it 'indexes each node on its own' do
      first = snippets.occurrence(2, node)
      expect([first, snippets.occurrence(2, semantic_node('Foo#bar', 1, 2))]).to eq(['(Occurrence 1 of 2).', ''])
    end
  end

  describe '.occurrence_label' do
    it 'numbers a line among the lines holding the same text' do
      expect(described_class.occurrence_label([3, 7, 9], 7)).to eq('(Occurrence 2 of 3).')
    end

    it 'labels nothing for a unique line' do
      expect(described_class.occurrence_label([3], 3)).to eq('')
    end

    it 'labels both lines of a pair' do
      expect([described_class.occurrence_label([3, 7], 3), described_class.occurrence_label([3, 7], 7)])
        .to eq(['(Occurrence 1 of 2).', '(Occurrence 2 of 2).'])
    end
  end

  describe '#branch_text' do
    it 'falls back to the full line range when column data is absent' do
      expect(snippets.branch_text(branch(2, 2), nil)).to eq('x = 1')
    end

    it 'uses the inline slice when column data is present' do
      expect(snippets.branch_text(branch(2, 2), [2, 3])).to eq('x')
    end

    it 'joins the lines of a multi-line branch even when column data is present' do
      expect(snippets.branch_text(branch(1, 2), [0, 3])).to eq('def bar x = 1')
    end
  end

  describe '.inline_slice' do
    it 'returns the byte slice of the branch line, stripped on both sides' do
      lines = ["def bar\n", "  x = 1\n", "  y = 2\n", "end\n"]
      exact = described_class.inline_slice(lines, 2..2, [2, 3])
      padded = described_class.inline_slice(lines, 3..3, [1, 6])
      expect([exact, padded]).to eq(['x', 'y ='])
    end

    it 'returns nil for a multi-line branch, whatever the columns' do
      expect(described_class.inline_slice(source_lines, 1..2, [0, 3])).to be_nil
    end

    it 'returns nil without column data' do
      expect(described_class.inline_slice(source_lines, 2..2, nil)).to be_nil
    end

    it 'returns nil when the branch line is beyond the source' do
      expect(described_class.inline_slice(source_lines, 99..99, [0, 2])).to be_nil
    end

    it 'returns nil when the column range exceeds the line length' do
      expect(described_class.inline_slice(source_lines, 2..2, [0, 999])).to be_nil
    end

    it 'reads the first line of the range' do
      expect(described_class.inline_slice(["a = 1\n", "b = 2\n"], 1..1, [0, 1])).to eq('a')
    end
  end

  describe '#cut' do
    it 'returns the first non-blank line of the range, stripped, and an ellipsis' do
      expect(snippets_of(["\n", "  elsif number.odd?\n", "  :odd\n"]).cut(1..3)).to eq('elsif number.odd?...')
    end

    it 'finds text on the last line of the range' do
      expect(snippets_of("\nlate\n".lines).cut(1..2)).to eq('late...')
    end

    it 'looks no further than the last line of the range' do
      expect(snippets_of("\nlate\n".lines).cut(1..1)).to eq('...')
    end

    it 'leaves only the ellipsis when the range is blank or beyond the source' do
      expect([snippets_of(["\n", "  \n"]).cut(1..2), snippets.cut(5..6)]).to eq(['...', '...'])
    end
  end
end
