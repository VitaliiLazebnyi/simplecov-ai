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
  # names it `#<Class:Owner>` (`phantom` and `ghost`, methods the resolver cannot see, on the
  # class's first line and at line 15). `sign_alias` sits inside `sign` without being it.
  let(:method_descriptors) do
    { ['Sample::Calc', :sign, 3, 4, 5, 7] => 3, ['Sample::Calc', :never_called, 7, 4, 9, 7] => 0,
      ['Sample::Calc', :build, 12, 6, 14, 9] => 0, ['#<Class:Sample::Calc>', :phantom, 2, 2, 2, 20] => 0,
      ['#<Class:Sample::Calc>', :ghost, 15, 2, 15, 20] => 0, ['Sample::Calc', :sign_alias, 4, 4, 4, 30] => 0 }
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
    expected_header('FAILED', '100.0%', '100.0%', method_label: '16.6%') + expected_method_deficits
  end

  def expected_method_deficits
    <<~MARKDOWN
      ## Coverage Deficits

      ### `calc.rb`
      - `Sample::Calc`
        - **Method Deficit:** [L2] `Sample::Calc.phantom` never invoked
        - **Method Deficit:** [L15] `Sample::Calc.ghost` never invoked
      - `Sample::Calc#sign`
        - **Method Deficit:** [L4] `Sample::Calc#sign_alias` never invoked
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

    # SimpleCov < 1.0 has neither Result#total_methods nor SourceFile#missed_methods.
    it 'reports no method figures at all on a SimpleCov without the method coverage API' do
      allow(result).to receive(:respond_to?).and_call_original
      allow(result).to receive(:respond_to?).with(:total_methods).and_return(false)
      allow(result).to receive(:total_methods).and_raise(NoMethodError)
      expect(digest_for(result)).to eq(expected_header('PASSED', '100.0%', '100.0%'))
    end

    it 'derives no method deficit from a file without the method coverage API' do
      file = result.files.first
      allow(file).to receive(:respond_to?).and_call_original
      allow(file).to receive(:respond_to?).with(:missed_methods).and_return(false)
      allow(file).to receive(:missed_methods).and_raise(NoMethodError)
      expect(described_class::MethodDeficit.from_file(file)).to eq([])
    end

    it 'names a method whose owner SimpleCov reports as a Module, as a live result does' do
      skip 'method coverage needs SimpleCov >= 1.0' unless method_coverage_supported?
      methods = { [described_class, :never_called, 7, 4, 9, 7] => 0 }
      live = source_file(calc_path, { 'lines' => perfect_lines, 'methods' => methods })
      expect(described_class::MethodDeficit.from_file(live).map(&:name)).to eq(["#{described_class}#never_called"])
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

  describe 'deficit files' do
    it 'lists files of equal coverage in path order, whatever order SimpleCov lists them in' do
      coverage_by_path = (1..12).to_h do |index|
        [write_source(tmpdir, format('tie%02d.rb', index), "def work\n  1\nend\n"), { 'lines' => [1, 0, nil] }]
      end
      result = result_for(coverage_by_path)
      allow(result).to receive(:files).and_return(SimpleCov::FileList.new(result.files.to_a.reverse))
      headings = digest_for(result).scan(/^### `(tie\d+\.rb)`$/).flatten
      expect(headings).to eq((1..12).map { |index| format('tie%02d.rb', index) })
    end

    # A then arm with columns and an else arm whose descriptor is too short for any.
    def long_arm_result
      source = "def pick(flag)\n  flag ? :#{'a' * 90} : :b\nend\n"
      long_then = branch_descriptor(source, :then, 1, 2, ":#{'a' * 90}")
      arms = { long_then => 0, branch_descriptor(source, :else, 2, 2, ':b').first(5) => 0 }
      branches = { branch_descriptor(source, :if, 0, 2, 'flag ?') => arms }
      result_for(write_source(tmpdir, 'pick.rb', source) => { 'lines' => [1, 1, nil], 'branches' => branches })
    end

    it 'quotes a branch without column data from its whole line, truncating both to the snippet budget' do
      config.max_snippet_lines = 1
      expect(digest_for(long_arm_result)).to end_with(<<~MARKDOWN)
        - `#pick`
          - **Branch Deficit:** [L2] Missing coverage for `then` branch: `:#{'a' * 79}...`
          - **Branch Deficit:** [L2] Missing coverage for `else` branch: `flag ? :#{'a' * 72}...`

      MARKDOWN
    end

    it 'lists a file whose lines are all covered but a branch is missed' do
      source = "def sign(number)\n  number.positive? ? :pos : :neg\nend\n"
      arms = { branch_descriptor(source, :then, 1, 2, ':pos') => 1,
               branch_descriptor(source, :else, 2, 2, ':neg') => 0 }
      branches = { branch_descriptor(source, :if, 0, 2, 'number.positive? ? :pos : :neg') => arms }
      result = result_for(write_source(tmpdir, 'sign.rb', source) => { 'lines' => [1, 1, nil], 'branches' => branches })
      expect(digest_for(result)).to eq(expected_header('FAILED', '100.0%', '50.0%') + <<~MARKDOWN)
        ## Coverage Deficits

        ### `sign.rb`
        - `#sign`
          - **Branch Deficit:** [L2] Missing coverage for `else` branch: `:neg`

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

    # The outer `else` arm ends on the same line as the inner `then` arm it encloses.
    def tail_source
      <<~RUBY
        def classify(number)
          if number.zero?
            :zero
          else
            parity = number.odd?
            :odd if parity
          end
        end
      RUBY
    end

    def tail_result
      source = tail_source
      outer_arms = { branch_descriptor(source, :then, 1, 3, ':zero') => 1,
                     multiline_branch_descriptor(:else, 2, 5, 6) => 0 }
      inner_arms = { branch_descriptor(source, :then, 4, 6, ':odd') => 0,
                     branch_descriptor(source, :else, 5, 6, ':odd if parity') => 0 }
      branches = { multiline_branch_descriptor(:if, 0, 2, 7) => outer_arms,
                   branch_descriptor(source, :if, 3, 6, ':odd if parity') => inner_arms }
      path = write_source(tmpdir, 'tail.rb', source)
      result_for(path => { 'lines' => line_hits(8, covered: [1, 2, 3], missed: [5, 6]), 'branches' => branches })
    end

    it 'cuts an arm that spans another missed arm ending on its last line' do
      expect(digest_for(tail_result)).to end_with(<<~MARKDOWN)
        - `#classify`
          - **Line Deficit:** [L5] `parity = number.odd?`
          - **Line Deficit:** [L6] `:odd if parity`
          - **Branch Deficit:** [L5-6] Missing coverage for `else` branch: `parity = number.odd?...`
          - **Branch Deficit:** [L6] Missing coverage for `then` branch: `:odd`
          - **Branch Deficit:** [L6] Missing coverage for `else` branch: `:odd if parity`

      MARKDOWN
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

    it 'names zero bypass files in the notice when only deficit files were left out' do
      config.max_file_size_kb = 1
      bulky_paths = bulky_result.files.first(3).map(&:filename)
      deficits_only = result_for(bulky_paths.to_h { |path| [path, { 'lines' => [1, 1, 0, nil, nil] }] })
      digest = digest_for(deficits_only)
      omitted = 3 - section_headings(digest, 'Coverage Deficits')
      expect(digest.lines.last(2).join).to eq(expected_notice(omitted, 0))
    end

    it 'counts no bypass files when bypass auditing is disabled' do
      config.max_file_size_kb = 1
      config.include_bypasses = false
      digest = digest_for(bulky_result)
      omitted = 3 - section_headings(digest, 'Coverage Deficits')
      expect(digest.lines.last(2).join).to eq(expected_notice(omitted, 0))
    end

    # Files after the one the budget stopped at are not resolved for the deficit section; the
    # bypass section still visits every file to count what it leaves out.
    it 'stops resolving deficit files once the budget has closed the section' do
      config.max_file_size_kb = 1
      builder = described_class.new(bulky_result, config)
      resolved = []
      allow(builder).to receive(:try_resolve_ast).and_wrap_original do |original, filename|
        resolved << File.basename(filename)
        original.call(filename)
      end
      builder.build
      expect(resolved).to eq(%w[bulky1.rb bulky2.rb skipped1.rb skipped2.rb])
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
