# typed: false
# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'open3'
require 'rbconfig'
require 'tmpdir'

# Drives the formatter the way a project does: a child Ruby process, sharing this suite's bundle
# (so it runs the installed SimpleCov), starts SimpleCov with branch coverage and its default
# result merging, loads a small fixture project written to a temporary directory, exercises part
# of it and lets SimpleCov's at_exit hook write the digest. SimpleCov merges through
# .resultset.json, so the formatter receives a result whose branch descriptors were stringified
# and decoded again — the path a real run takes, and the one the in-process specs cannot fake.
module EndToEnd
  LIB_DIR = File.expand_path('../../lib', __dir__)
  NOCOV = SimpleCovFixtures::NOCOV_MARKER

  # What a child run produced: its streams and exit status, the digest it wrote (nil when it
  # wrote none) and the descriptor classes the probe formatter saw (see RUNNER).
  Run = Struct.new(:stdout, :stderr, :status, :report, :descriptor_classes)

  # One covered method with a missed ternary arm, one never-invoked method with a repeated
  # statement, and one never-invoked method whose only line is a backtick command.
  CALC_SOURCE = <<~RUBY
    # frozen_string_literal: true

    module Shapes
      class Calc
        def sign(number)
          number.positive? ? :pos : :neg
        end

        def never_called
          @never = 1
          @never = 1
        end

        def shell
          `echo hi`
        end
      end
    end
  RUBY

  # Every bypass form: a nocov pair, an inline `simplecov:disable` and a `simplecov:disable
  # branch` block (the latter two are honoured by SimpleCov >= 1.0 only).
  LEGACY_SOURCE = <<~RUBY
    # frozen_string_literal: true

    module Shapes
      class Legacy
        #{NOCOV}
        def obsolete
          raise NotImplementedError
        end
        #{NOCOV}

        def fail_loudly
          raise 'x' # simplecov:disable
        end

        def pick(flag)
          # simplecov:disable branch
          flag ? :yes : :no
          # simplecov:enable branch
        end
      end
    end
  RUBY

  # A Struct.new block, a top-level nocov region and a top-level branch, so root-scope
  # attribution shows up for a deficit and for a bypass.
  POINT_SOURCE = <<~RUBY
    # frozen_string_literal: true

    Point = Struct.new(:x, :y) do
      def side
        x.positive? ? :right : :left
      end
    end

    #{NOCOV}
    DEBUG = ENV.key?('SHAPES_DEBUG')
    #{NOCOV}

    puts 'debugging' if DEBUG
  RUBY

  # The child's script. The probe formatter records the class of the branch descriptors the
  # formatters receive: Strings prove the result came back through the resultset merge.
  RUNNER = <<~'RUBY'
    # frozen_string_literal: true

    require 'simplecov'
    require 'simplecov-ai'

    class DescriptorProbe
      def format(result)
        descriptors = result.original_result.values.flat_map { |coverage| (coverage['branches'] || {}).keys }
        classes = descriptors.map { |descriptor| descriptor.class.name }.uniq.sort
        File.write(File.join(SimpleCov.coverage_path, 'descriptor_classes.txt'), classes.join(','))
      end
    end

    SimpleCov.root(__dir__)
    SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter.new([SimpleCov::Formatter::AIFormatter, DescriptorProbe])
    SimpleCov::Formatter::AIFormatter.configure do |config|
      config.max_file_size_kb = Integer(ENV['SCAI_E2E_MAX_KB']) if ENV.key?('SCAI_E2E_MAX_KB')
    end
    SimpleCov.start do
      enable_coverage :branch
      enable_coverage :method if ENV['SCAI_E2E_METHODS'] == '1'
    end

    require_relative 'lib/shapes/calc'
    require_relative 'lib/shapes/legacy'
    require_relative 'lib/shapes/point'

    Shapes::Calc.new.sign(5)
    Shapes::Legacy.new.pick(true)
    Point.new(2, 0).side
  RUBY

  module_function

  # Writes the fixture project (sources under lib/shapes and the runner) into `project_dir`.
  def write_project(project_dir)
    FileUtils.mkdir_p(File.join(project_dir, 'lib', 'shapes'))
    File.write(File.join(project_dir, 'lib', 'shapes', 'calc.rb'), CALC_SOURCE)
    File.write(File.join(project_dir, 'lib', 'shapes', 'legacy.rb'), LEGACY_SOURCE)
    File.write(File.join(project_dir, 'lib', 'shapes', 'point.rb'), POINT_SOURCE)
    File.write(File.join(project_dir, 'run.rb'), RUNNER)
  end

  # Runs the project in a child Ruby that inherits this process's environment (Bundler's
  # RUBYOPT and BUNDLE_GEMFILE included, so it sees the same gems) plus `env`.
  def run(project_dir, env = {})
    stdout, stderr, status = Open3.capture3(env, RbConfig.ruby, '-I', LIB_DIR, File.join(project_dir, 'run.rb'))
    coverage_dir = File.join(project_dir, 'coverage')
    report = File.join(coverage_dir, 'ai_report.md')
    probe = File.join(coverage_dir, 'descriptor_classes.txt')
    Run.new(stdout, stderr, status, File.exist?(report) ? File.read(report) : nil,
            File.exist?(probe) ? File.read(probe) : nil)
  end

  # The child writes the report at SimpleCov.root, which Ruby resolves through symlinks.
  def report_path(project_dir)
    File.join(File.realpath(project_dir), 'coverage', 'ai_report.md')
  end
end

RSpec.describe EndToEnd do
  let(:project_dir) { Dir.mktmpdir('scai-e2e') }
  # SimpleCov >= 1.0 honours `# simplecov:disable`; older releases see plain code there.
  let(:directives) { simplecov_directives_supported? }
  let(:announcement) { "AI coverage digest written to #{described_class.report_path(project_dir)}\n" }

  before { described_class.write_project(project_dir) }

  after { FileUtils.remove_entry(project_dir) }

  def normalise(report)
    report.to_s.sub(/^\*\*Generated At:\*\* \S+/, '**Generated At:** TIMESTAMP')
  end

  def iso8601_timestamp?(report)
    report.to_s.match?(/^\*\*Generated At:\*\* \d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:Z|[+-]\d{2}:\d{2}) \(Local Timezone\)$/)
  end

  def gem_warnings(stderr)
    stderr.lines.select { |line| line.include?(described_class::LIB_DIR) }
  end

  def header(line_pct, method_pct: nil)
    method_line = method_pct ? "**Global Method Coverage:** #{method_pct}\n" : ''
    "# AI Coverage Digest\n**Status:** FAILED\n**Global Line Coverage:** #{line_pct}\n" \
      "**Global Branch Coverage:** 50.0%\n#{method_line}**Generated At:** TIMESTAMP (Local Timezone)\n"
  end

  # A file block: its heading, the given entry lines and the blank line that closes it.
  def file_block(path, *entries)
    "#{["### `#{path}`", *entries].join("\n")}\n\n"
  end

  def method_deficit(lines, name)
    "  - **Method Deficit:** [L#{lines}] `#{name}` never invoked"
  end

  def calc_deficits(method_deficits: false)
    file_block('lib/shapes/calc.rb',
               '- `Shapes::Calc#sign`',
               '  - **Branch Deficit:** [L6] Missing coverage for `else` branch: `:neg`',
               '- `Shapes::Calc#never_called`',
               *(method_deficits ? [method_deficit('9-12', 'Shapes::Calc#never_called')] : []),
               '  - **Line Deficit:** [L10] `@never = 1` (Occurrence 1 of 2).',
               '  - **Line Deficit:** [L11] `@never = 1` (Occurrence 2 of 2).',
               '- `Shapes::Calc#shell`',
               *(method_deficits ? [method_deficit('14-16', 'Shapes::Calc#shell')] : []),
               '  - **Line Deficit:** [L15] `` `echo hi` ``')
  end

  # Without directive support the inline-disabled line and the branch-disabled arm are
  # ordinary deficits; with method coverage the never-invoked method is one everywhere.
  def legacy_deficits(method_deficits: false)
    if method_deficits
      file_block('lib/shapes/legacy.rb', '- `Shapes::Legacy#fail_loudly`',
                 method_deficit('11-13', 'Shapes::Legacy#fail_loudly'))
    else
      file_block('lib/shapes/legacy.rb',
                 '- `Shapes::Legacy#fail_loudly`',
                 "  - **Line Deficit:** [L12] `raise 'x' # simplecov:disable`",
                 '- `Shapes::Legacy#pick`',
                 '  - **Branch Deficit:** [L17] Missing coverage for `else` branch: `:no`')
    end
  end

  def point_deficits
    file_block('lib/shapes/point.rb',
               '- `main`',
               "  - **Branch Deficit:** [L13] Missing coverage for `then` branch: `puts 'debugging'`",
               '- `Point#side`',
               '  - **Branch Deficit:** [L5] Missing coverage for `else` branch: `:left`')
  end

  def bypass(node, reason)
    ["- `#{node}`", "  - **Bypass Present:** Coverage explicitly ignored via `#{reason}`."]
  end

  def bypasses
    legacy_entries = bypass('Shapes::Legacy#obsolete', described_class::NOCOV)
    if directives
      legacy_entries += bypass('Shapes::Legacy#fail_loudly', '# simplecov:disable')
      legacy_entries += bypass('Shapes::Legacy#pick', '# simplecov:disable branch')
    end
    "## Ignored Coverage Bypasses\n\n" + file_block('lib/shapes/legacy.rb', *legacy_entries) +
      file_block('lib/shapes/point.rb', *bypass('main', described_class::NOCOV))
  end

  def expected_default_report
    deficits = calc_deficits + (directives ? '' : legacy_deficits) + point_deficits
    "#{header(directives ? '83.3%' : '78.9%')}## Coverage Deficits\n\n#{deficits}#{bypasses}"
  end

  def expected_method_report
    deficits = calc_deficits(method_deficits: true) + legacy_deficits(method_deficits: true) + point_deficits
    "#{header('83.3%', method_pct: '50.0%')}## Coverage Deficits\n\n#{deficits}#{bypasses}"
  end

  it 'writes the exact digest through SimpleCov\'s merged result, announces it and emits no warning of its own' do
    child = described_class.run(project_dir)
    expect([normalise(child.report), iso8601_timestamp?(child.report), child.stdout, child.status.exitstatus,
            child.descriptor_classes, gem_warnings(child.stderr)])
      .to eq([expected_default_report, true, announcement, 0, 'String', []])
  end

  it 'keeps a 1 kB report within 1000 bytes and closes it with the truncation notice' do
    child = described_class.run(project_dir, 'SCAI_E2E_MAX_KB' => '1')
    report = child.report.to_s
    omitted_deficits = (directives ? 2 : 3) - report[/## Coverage Deficits.*?(?=\n## |\z)/m].to_s.scan(/^### /).size
    omitted_bypasses = 2 - report[/## Ignored Coverage Bypasses.*?\z/m].to_s.scan(/^### /).size
    expect([report.bytesize <= 1000, report.lines.last(2).join]).to eq([true, <<~MARKDOWN])
      > **[WARNING] TRUNCATION NOTIFICATION:**
      > The report reached the maximum token constraint (1 kB) and was truncated: #{omitted_deficits} deficit file(s) and #{omitted_bypasses} bypass file(s) omitted or cut short. Lowest-coverage files are listed first; resolve the deficits above to reveal the remaining ones in subsequent test runs.
    MARKDOWN
  end

  it 'reports the method line and every never-invoked method with method coverage on (SimpleCov >= 1.0)' do
    skip 'method coverage needs SimpleCov >= 1.0' unless method_coverage_supported?
    child = described_class.run(project_dir, 'SCAI_E2E_METHODS' => '1')
    expect([normalise(child.report), child.stdout, child.status.exitstatus, gem_warnings(child.stderr)])
      .to eq([expected_method_report, announcement, 0, []])
  end
end
