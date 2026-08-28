# typed: false
# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require 'tmpdir'

RSpec.describe SimpleCov::Formatter::AIFormatter::MarkdownBuilder::SectionWriter do
  let(:buffer) { StringIO.new }
  # A 1 kB budget with the notice reserve leaves roughly 700 admissible bytes.
  let(:budget) { SimpleCov::Formatter::AIFormatter::MarkdownBuilder::ReportBudget.new(buffer, 1, 0) }
  let(:writer) { described_class.new(budget, "## Section\n\n") }

  it 'emits the section heading with the first block and separates blocks with a blank line' do
    writer.write_file_block('### `a.rb`', ["- `A`\n"])
    writer.write_file_block('### `b.rb`', ["- `B`\n", "- `C`\n"])
    expect([buffer.string, writer.written_blocks, writer.closed?])
      .to eq(["## Section\n\n### `a.rb`\n- `A`\n\n### `b.rb`\n- `B`\n- `C`\n\n", 2, false])
  end

  it 'writes nothing and closes when the very first block does not fit' do
    writer.write_file_block('### `a.rb`', ['x' * 800])
    expect([buffer.string, writer.written_blocks, writer.closed?]).to eq(['', 0, true])
  end

  it 'cuts a block short at node granularity, keeps the blank line and counts the block as unwritten' do
    writer.write_file_block('### `a.rb`', ["#{'a' * 400}\n", "#{'b' * 400}\n", "#{'c' * 10}\n"])
    expect([buffer.string, writer.written_blocks, writer.closed?])
      .to eq(["## Section\n\n### `a.rb`\n#{'a' * 400}\n\n", 0, true])
  end

  it 'does not add a separator when a later block is rejected outright' do
    writer.write_file_block('### `a.rb`', ["#{'a' * 300}\n"])
    writer.write_file_block('### `b.rb`', ["#{'b' * 500}\n"])
    expect([buffer.string, writer.written_blocks]).to eq(["## Section\n\n### `a.rb`\n#{'a' * 300}\n\n", 1])
  end

  it 'ignores every block once closed' do
    writer.write_file_block('### `a.rb`', ['x' * 800])
    writer.write_file_block('### `b.rb`', ['tiny'])
    expect(buffer.string).to eq('')
  end

  it 'renders a file heading from the project-relative path inside a code span' do
    Dir.mktmpdir('scai') do |tmpdir|
      allow(SimpleCov).to receive(:root).and_return(tmpdir)
      path = write_source(tmpdir, 'weird`name.rb', "1\n")
      expect(described_class.file_heading(source_file(path, { 'lines' => [1] }))).to eq('### ``weird`name.rb``')
    end
  end

  it 'drops the leading slash SimpleCov < 1.0 keeps on the project-relative path' do
    Dir.mktmpdir('scai') do |tmpdir|
      file = source_file(write_source(tmpdir, 'legacy.rb', "1\n"), { 'lines' => [1] })
      allow(file).to receive(:project_filename).and_return('/lib/legacy.rb')
      expect(described_class.file_heading(file)).to eq('### `lib/legacy.rb`')
    end
  end
end
