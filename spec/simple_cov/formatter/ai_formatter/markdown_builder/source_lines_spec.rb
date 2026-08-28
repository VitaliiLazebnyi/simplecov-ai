# typed: false
# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'

RSpec.describe SimpleCov::Formatter::AIFormatter::MarkdownBuilder::SourceLines do
  let(:tmpdir) { Dir.mktmpdir('scai') }
  let(:file) { source_file(write_source(tmpdir, 'lines.rb', "def a\n  1\nend\n"), { 'lines' => [1, 1, nil] }) }

  after { FileUtils.remove_entry(tmpdir) }

  it 'returns the lines SimpleCov loaded, trailing newlines included' do
    expect(described_class.of(file)).to eq(["def a\n", "  1\n", "end\n"])
  end

  it 'scrubs invalid byte sequences SimpleCov < 1.1 leaves in the source' do
    allow(file).to receive(:src).and_return(["# Latin-1 \xe9\n", "1\n"])
    expect(described_class.of(file)).to eq(["# Latin-1 �\n", "1\n"])
  end

  it 'returns no lines when the source cannot be read' do
    allow(file).to receive(:src).and_raise(Errno::EACCES)
    expect(described_class.of(file)).to eq([])
  end
end
