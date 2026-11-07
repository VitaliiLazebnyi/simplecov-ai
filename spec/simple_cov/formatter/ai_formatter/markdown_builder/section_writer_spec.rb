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

  describe '#write_blocks' do
    it 'emits the section heading with the first block and separates blocks with a blank line' do
      omitted = writer.write_blocks([['### `a.rb`', ["- `A`\n"]], ['### `b.rb`', ["- `B`\n", "- `C`\n"]]])
      expect([buffer.string, omitted]).to eq(["## Section\n\n### `a.rb`\n- `A`\n\n### `b.rb`\n- `B`\n- `C`\n\n", 0])
    end

    it 'writes nothing when the very first block does not fit, and counts every block as omitted' do
      omitted = writer.write_blocks([['### `a.rb`', ['x' * 800]], ['### `b.rb`', ['tiny']]])
      expect([buffer.string, omitted]).to eq(['', 2])
    end

    it 'cuts a block short at node granularity, keeps the blank line and counts the block as omitted' do
      omitted = writer.write_blocks([['### `a.rb`', ["#{'a' * 400}\n", "#{'b' * 400}\n", "#{'c' * 10}\n"]]])
      expect([buffer.string, omitted]).to eq(["## Section\n\n### `a.rb`\n#{'a' * 400}\n\n", 1])
    end

    it 'does not add a separator when a later block is rejected outright' do
      omitted = writer.write_blocks([['### `a.rb`', ["#{'a' * 300}\n"]], ['### `b.rb`', ["#{'b' * 500}\n"]]])
      expect([buffer.string, omitted]).to eq(["## Section\n\n### `a.rb`\n#{'a' * 300}\n\n", 1])
    end

    it 'writes no later block once a block was cut short, however small' do
      blocks = [['### `a.rb`', ["#{'a' * 400}\n", "#{'b' * 400}\n"]], ['### `b.rb`', ['tiny']]]
      expect([writer.write_blocks(blocks), buffer.string]).to eq([2, "## Section\n\n### `a.rb`\n#{'a' * 400}\n\n"])
    end

    it 'emits the section heading once, with the first block only' do
      writer.write_blocks([['### `a.rb`', ["- `A`\n"]]])
      writer.write_blocks([['### `b.rb`', ["- `B`\n"]]])
      expect(buffer.string).to eq("## Section\n\n### `a.rb`\n- `A`\n\n### `b.rb`\n- `B`\n\n")
    end
  end

  describe '#write_files' do
    let(:tmpdir) { Dir.mktmpdir('scai') }
    let(:files) do
      %w[a b c].map { |name| source_file(write_source(tmpdir, "#{name}.rb", "1\n"), { 'lines' => [0] }) }
    end

    before { allow(SimpleCov).to receive(:root).and_return(tmpdir) }

    after { FileUtils.remove_entry(tmpdir) }

    it 'renders and writes each file under its heading' do
      omitted = writer.write_files(files.first(2)) { |file| ["- `#{File.basename(file.filename)}`\n"] }
      expect([buffer.string, omitted])
        .to eq(["## Section\n\n### `a.rb`\n- `a.rb`\n\n### `b.rb`\n- `b.rb`\n\n", 0])
    end

    it 'stops rendering once the section is closed and counts the files left out' do
      rendered = []
      omitted = writer.write_files(files) do |file|
        rendered << File.basename(file.filename)
        [rendered.size == 1 ? "#{'a' * 400}\n#{'b' * 400}\n" : "- tiny\n"]
      end
      expect([rendered, omitted, buffer.string]).to eq([['a.rb'], 3, ''])
    end
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
