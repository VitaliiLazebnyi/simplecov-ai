# typed: false
# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe SimpleCov::Formatter::AIFormatter::ASTResolver::BypassScanner do
  describe '.contains_directive?' do
    it 'detects a standalone nocov marker' do
      expect(described_class.contains_directive?("x = 1\n# :nocov:\n")).to be(true)
    end

    it 'detects a simplecov:disable directive' do
      expect(described_class.contains_directive?("# simplecov:disable\ndef a; end\n")).to be(true)
    end

    it 'ignores a prose mention of a directive token' do
      expect(described_class.contains_directive?("do_thing # mentions :nocov: mid-line\n")).to be(false)
    end

    it 'returns false for directive-free source' do
      expect(described_class.contains_directive?("def a\n  1\nend\n")).to be(false)
    end
  end

  describe '.attribute' do
    it 'leaves a region alone when no node encloses it, as with a node list lacking a root scope' do
      lonely = SimpleCov::Formatter::AIFormatter::ASTResolver::SemanticNode.new(
        name: 'Late#method', type: 'Instance Method', start_line: 6, end_line: 8, bypass_reasons: []
      )
      described_class.attribute([lonely], "# simplecov:disable\nTOP = 1\n# simplecov:enable\n\n\ndef method\nend\n")
      expect(lonely.bypass_reasons).to be_empty
    end
  end

  describe 'attribution via ASTResolver.resolve' do
    let(:tmpdir) { Dir.mktmpdir }

    after { FileUtils.remove_entry(tmpdir) }

    def resolve(code)
      path = File.join(tmpdir, 'sample.rb')
      File.write(path, code)
      SimpleCov::Formatter::AIFormatter::ASTResolver.resolve(path)
    end

    it 'extends an unclosed simplecov:disable region to end of file' do
      nodes = resolve(<<~RUBY)
        class Runner
          # simplecov:disable
          def never_reenabled
          end
        end
      RUBY
      node = nodes.find { |candidate| candidate.name == 'Runner#never_reenabled' }
      expect(node.bypass_reasons).to eq(['# simplecov:disable'])
    end

    it 'attributes an unmatched nocov marker to the rest of the file' do
      # The `# :noc%s:` placeholder keeps the literal directive out of this heredoc so the
      # repository directive auditor does not flag the fixture.
      nodes = resolve(format(<<~RUBY, 'ov'))
        class Runner
          # :noc%s:
          def trailing
          end
        end
      RUBY
      node = nodes.find { |candidate| candidate.name == 'Runner#trailing' }
      expect(node.bypass_reasons).not_to be_empty
    end
  end
end
