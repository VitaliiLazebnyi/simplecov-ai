# typed: false
# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'

RSpec.describe SimpleCov::Formatter::AIFormatter::MarkdownBuilder do
  let(:tmpdir) { Dir.mktmpdir('scai') }
  let(:config) { SimpleCov::Formatter::AIFormatter::Configuration.new }
  let(:calc_path) { write_source(tmpdir, 'calc.rb', calc_source) }
  let(:perfect_lines) { line_hits(17, covered: [1, 2, 3, 4, 7, 8, 11, 12, 13]) }
  # SimpleCov's merged data names a singleton method's owner plainly (`build`); a live result
  # names it `#<Class:Owner>` (`ghost`, a method the resolver cannot see, defined at line 15).
  let(:method_descriptors) do
    { ['Sample::Calc', :sign, 3, 4, 5, 7] => 3, ['Sample::Calc', :never_called, 7, 4, 9, 7] => 0,
      ['Sample::Calc', :build, 12, 6, 14, 9] => 0, ['#<Class:Sample::Calc>', :ghost, 15, 2, 15, 20] => 0 }
  end

  before do
    allow(SimpleCov).to receive(:root).and_return(tmpdir)
    freeze_time
  end

  after { FileUtils.remove_entry(tmpdir) }

  def calc_source
    <<~RUBY
      module Sample
        class Calc
          def sign(number)
            number.positive? ? :pos : :neg
          end

          def never_called
            :never
          end

          class << self
            def build
              new
            end
          end
        end
      end
    RUBY
  end

  def digest_for(result)
    described_class.new(result, config).build
  end

  def expected_method_digest
    expected_header('FAILED', '100.0%', '100.0%', method_label: '25.0%') + <<~MARKDOWN
      ## Coverage Deficits

      ### `calc.rb`
      - `Sample::Calc`
        - **Method Deficit:** [L15] `Sample::Calc.ghost` never invoked
      - `Sample::Calc#never_called`
        - **Method Deficit:** [L7-9] `Sample::Calc#never_called` never invoked
      - `Sample::Calc.build`
        - **Method Deficit:** [L12-14] `Sample::Calc.build` never invoked

    MARKDOWN
  end

  def expected_notice(omitted_deficits, omitted_bypasses)
    "> **[WARNING] TRUNCATION NOTIFICATION:**\n> The report reached the maximum token constraint (1 kB) and was " \
      "truncated: #{omitted_deficits} deficit file(s) and #{omitted_bypasses} bypass file(s) omitted or cut short. " \
      'Lowest-coverage files are listed first; resolve the deficits above to reveal the remaining ones in ' \
      "subsequent test runs.\n"
  end

  describe 'header percentages' do
    it 'prints one decimal without ever rounding a partial figure up to 100.0' do
      result = result_for(calc_path => { 'lines' => perfect_lines })
      allow(result).to receive(:covered_percent).and_return(99.96)
      expect(digest_for(result)).to eq(expected_header('FAILED', '99.9%', '100.0%'))
    end
  end

  describe 'method coverage' do
    let(:result) { result_for(calc_path => { 'lines' => perfect_lines, 'methods' => method_descriptors }) }

    it 'adds the method line to the header, fails the status and lists each missed method under its node' do
      digest = measuring_methods(result, calc_path => method_descriptors) { digest_for(result) }
      expect(digest).to eq(expected_method_digest)
    end

    it 'keeps the header byte-identical and the status PASSED when method coverage is not measured' do
      expect(digest_for(result)).to eq(expected_header('PASSED', '100.0%', '100.0%'))
    end

    it 'lists missed methods under the raw line numbers when the AST cannot be resolved' do
      broken_path = write_source(tmpdir, 'broken.rb', "class Broken\n  def half\n    1 +\n  end\n")
      methods = { ['Broken', :half, 2, 2, 4, 5] => 0 }
      broken = result_for(broken_path => { 'lines' => [1, 1, 0, nil], 'methods' => methods })
      digest = measuring_methods(broken, broken_path => methods) { digest_for(broken) }
      expect(digest).to eq(expected_header('FAILED', '66.6%', '100.0%', method_label: '0.0%') + <<~MARKDOWN)
        ## Coverage Deficits

        ### `broken.rb`
          - **ERROR:** AST Parsing Failed. Showing raw line numbers instead.
          - **Method Deficit:** [L2-4] `Broken#half` never invoked
          - **Line Deficit:** [L3] `1 +`

      MARKDOWN
    end
  end

  describe 'branch snippets' do
    let(:chain_source) do
      <<~RUBY
        def classify(number)
          if number.zero?
            :zero
          elsif number.odd?
            :odd
          else
            :even
          end
        end
      RUBY
    end
    let(:chain_result) do
      outer_arms = { branch_descriptor(chain_source, :then, 1, 3, ':zero') => 1,
                     multiline_branch_descriptor(:else, 2, 4, 8) => 0 }
      inner_arms = { branch_descriptor(chain_source, :then, 4, 5, ':odd') => 0,
                     branch_descriptor(chain_source, :else, 5, 7, ':even') => 0 }
      branches = { multiline_branch_descriptor(:if, 0, 2, 8) => outer_arms,
                   multiline_branch_descriptor(:if, 3, 4, 8) => inner_arms }
      path = write_source(tmpdir, 'chain.rb', chain_source)
      result_for(path => { 'lines' => line_hits(9, covered: [1, 2, 3], missed: [4, 5, 7]), 'branches' => branches })
    end

    it 'cuts an arm that spans other missed arms of the same node to its first line' do
      expect(digest_for(chain_result)).to eq(expected_header('FAILED', '50.0%', '25.0%') + <<~MARKDOWN)
        ## Coverage Deficits

        ### `chain.rb`
        - `#classify`
          - **Line Deficit:** [L4] `elsif number.odd?`
          - **Line Deficit:** [L5] `:odd`
          - **Line Deficit:** [L7] `:even`
          - **Branch Deficit:** [L4-8] Missing coverage for `else` branch: `elsif number.odd?...`
          - **Branch Deficit:** [L5] Missing coverage for `then` branch: `:odd`
          - **Branch Deficit:** [L7] Missing coverage for `else` branch: `:even`

      MARKDOWN
    end
  end

  describe 'size budget' do
    let(:bulky_result) do
      coverage_by_path = (1..3).to_h do |index|
        body = "    @value#{index} = '#{'a' * 300}'\n"
        source = "class Bulky#{index}\n  def work\n#{body}  end\nend\n"
        [write_source(tmpdir, "bulky#{index}.rb", source), { 'lines' => [1, 1, 0, nil, nil] }]
      end
      bypass_paths(2).each { |path| coverage_by_path[path] = { 'lines' => [1, nil, 1, 1, nil, nil, nil] } }
      result_for(coverage_by_path)
    end

    def bypass_paths(count)
      (1..count).map do |index|
        source = "class Skipped#{index}\n  #{nocov_marker}\n  def hidden\n    :hidden\n  end\n  #{nocov_marker}\nend\n"
        write_source(tmpdir, "skipped#{index}.rb", source)
      end
    end

    def section_headings(digest, section)
      (digest[/## #{section}.*?(?=\n## |\z)/m] || '').scan(/^### /).size
    end

    it 'never exceeds the configured ceiling and closes with a single notice naming what was left out' do
      config.max_file_size_kb = 1
      digest = digest_for(bulky_result)
      omitted_deficits = 3 - section_headings(digest, 'Coverage Deficits')
      omitted_bypasses = 2 - section_headings(digest, 'Ignored Coverage Bypasses')
      expect([digest.bytesize <= 1000, digest.lines.last(2).join])
        .to eq([true, expected_notice(omitted_deficits, omitted_bypasses)])
    end

    it 'still lists the lowest-coverage file first when truncating' do
      config.max_file_size_kb = 1
      expect(digest_for(bulky_result)).to match(/## Coverage Deficits\n\n### `bulky1\.rb`\n- `Bulky1#work`\n/)
    end

    it 'emits no notice when everything fits' do
      expect(digest_for(bulky_result)).not_to include('TRUNCATION')
    end

    it 'counts an overflowing bypass section toward the same budget even without deficits' do
      config.max_file_size_kb = 1
      bypass_only = result_for(bypass_paths(30).to_h { |path| [path, { 'lines' => [1, nil, 1, 1, nil, nil, nil] }] })
      digest = digest_for(bypass_only)
      omitted_bypasses = 30 - section_headings(digest, 'Ignored Coverage Bypasses')
      expect([digest.bytesize <= 1000, digest.lines.last(2).join]).to eq([true, expected_notice(0, omitted_bypasses)])
    end
  end
end
