# typed: strict
# frozen_string_literal: true

require 'open3'
require 'tmpdir'
require 'rspec/core/rake_task'
require 'sorbet-runtime'

# `bundle exec rake` runs every gate CI enforces (see CONTRIBUTING.md); each one is also a task
# of its own. Mutation testing (`rake mutant`) and the dependency freshness check
# (`rake outdated`) are enforced in CI as well but kept out of the default task: the first takes
# minutes, the second needs the network.

# Flay mass threshold. Below it Flay only reports Sorbet `sig` declarations that two methods
# share (mass 32 at most in lib/); from it up every duplicated piece of logic is reported.
FLAY_MASS = 33
# Flog score above which a single method counts as too complex and must be split up.
FLOG_METHOD_THRESHOLD = 30
# Output of `yard stats` when every API object is documented.
FULLY_DOCUMENTED = '100.00% documented'
# Methods debride cannot see a caller for, each with the caller it cannot see.
DEBRIDE_ALLOWED = {
  'configure' => 'public API: called from the test helper of the project being measured',
  'reset_configuration!' => 'public API: called by test suites between examples',
  'report_path_configured?' => 'public API of Configuration',
  'string_value' => 'called by the parser builder LenientLiterals is extended onto'
}.freeze
# Docker images the `check:*` tasks run the suite in through bin/check-ruby. The official jruby
# image ships no C compiler, which prism (pulled in through parser's dependents) needs to build,
# so the JRuby task installs one before `bundle install`.
JRUBY_IMAGE = 'jruby:10.0'
JRUBY_SETUP = 'apt-get update -qq && apt-get install -y -qq build-essential'
TRUFFLERUBY_IMAGE = 'ghcr.io/graalvm/truffleruby-community:latest'

# Runs the tools whose report, not exit status, says whether they found anything.
module Report
  extend T::Sig

  # Prints a tool's report and fails unless it contains the line that means "no findings".
  #
  # @param command [Array<String>] The tool's command line.
  # @param clean [String] The text the report holds when there is nothing to fix.
  # @param failure [String] The message to abort with otherwise.
  # @return [void]
  sig { params(command: T::Array[String], clean: String, failure: String).void }
  def self.require_clean(command, clean, failure)
    output, status = Open3.capture2e(*command)
    puts output
    abort failure unless status.success? && output.include?(clean)
  end
end

# `-w` turns on Ruby's verbose warnings; spec/support/warnings.rb fails the suite on any warning
# raised by the gem's own files or the specs, exactly as the CI test jobs run.
RSpec::Core::RakeTask.new(:spec) { |task| task.ruby_opts = '-w' }

desc 'Run RuboCop with its plugins (no todo file, no inline directives)'
task :rubocop do
  sh 'bundle', 'exec', 'rubocop'
end

desc 'Fail on inline suppressions of any linter, scanner, type checker, warning or test'
task :suppressions do
  sh 'script/forbidden_suppressions.sh'
end

desc 'Generate the gem RBIs with Tapioca, then type-check with Sorbet (lib/ is typed: strong)'
task :typecheck do
  sh 'bundle', 'exec', 'tapioca', 'gem', 'ast', 'parser', 'prism', 'racc', 'simplecov'
  sh 'bundle', 'exec', 'srb', 'tc'
end

desc 'Build the YARD documentation (warnings are fatal) and require 100% documentation coverage'
task :yard do
  sh 'bundle', 'exec', 'yardoc', '--fail-on-warning'
  Report.require_clean(%w[bundle exec yard stats --list-undoc], FULLY_DOCUMENTED,
                       'YARD: undocumented API objects found')
end

desc 'Fail on any code smell (reek, default configuration; see .reek.yml)'
task :reek do
  sh 'bundle', 'exec', 'reek', 'lib'
end

desc 'Fail on any structural duplication (flay)'
task :flay do
  Report.require_clean(['bundle', 'exec', 'flay', '--mass', FLAY_MASS.to_s, 'lib'], 'Total score (lower is better) = 0',
                       'Flay: duplicated code found')
end

desc "Fail on any method with a flog score above #{FLOG_METHOD_THRESHOLD}"
task :flog do
  report, status = Open3.capture2e('bundle', 'exec', 'flog', '--all', '--methods-only', 'lib')
  puts report
  abort 'flog failed' unless status.success?
  scores = report.scan(%r{^\s*(\d+\.\d+): (\S+)\s+lib/})
  complex = scores.filter_map { |score, name| name if Float(score) > FLOG_METHOD_THRESHOLD }
  abort "flog: methods scoring above #{FLOG_METHOD_THRESHOLD}: #{complex.join(', ')}" unless complex.empty?
end

desc 'Fail on any method nothing calls (debride; see DEBRIDE_ALLOWED in the Rakefile)'
task :debride do
  Dir.mktmpdir('debride') do |dir|
    allowed = File.join(dir, 'allowed.txt')
    File.write(allowed, DEBRIDE_ALLOWED.keys.join("\n"))
    Report.require_clean(['bundle', 'exec', 'debride', '--whitelist', allowed, 'lib'], 'Total suspect LOC: 0',
                         'debride: methods without a caller found')
  end
end

desc 'Audit the locked dependency set against the Ruby Advisory Database'
task :audit do
  sh 'bundle', 'exec', 'bundler-audit', 'check', '--update'
end

desc 'Build the gem strictly (warnings are fatal), then install and require it from a clean GEM_HOME'
task :build do
  gemspec = Gem::Specification.load('simplecov-ai.gemspec')
  gem_file = "#{gemspec.name}-#{gemspec.version}.gem"
  sh 'gem', 'build', 'simplecov-ai.gemspec', '--strict'
  sh 'gem', 'specification', gem_file, 'version'
  Dir.mktmpdir('simplecov-ai-smoke') do |gem_home|
    # Drop Bundler's environment so the smoke test sees only the freshly installed gem.
    clean_env = { 'GEM_HOME' => gem_home, 'GEM_PATH' => gem_home, 'RUBYOPT' => nil, 'RUBYLIB' => nil,
                  'BUNDLE_GEMFILE' => nil, 'BUNDLE_BIN_PATH' => nil, 'BUNDLER_SETUP' => nil }
    sh clean_env, 'gem', 'install', '--no-document', gem_file
    sh clean_env, 'ruby', '-w', '-e',
       'require "simplecov-ai"; puts "Loaded simplecov-ai " + SimpleCov::Formatter::AIFormatter::VERSION'
  end
end

desc 'Mutation testing of lib/ with mutant (see .mutant.yml); MUTANT_SINCE=<revision> limits it to touched subjects'
task :mutant do
  command = %w[bundle exec mutant run]
  command.push('--since', ENV.fetch('MUTANT_SINCE')) if ENV.key?('MUTANT_SINCE')
  sh(*command)
end

desc 'Fail on any outdated Ruby, gem or GitHub Action not on the documented hold list (script/outdated_holds.yml)'
task :outdated do
  ruby 'script/outdated.rb'
end

# `rake check:jruby`, `rake check:truffleruby` and `rake 'check:ruby[2.7]'` run the suite on another
# Ruby inside its official Docker image (bin/check-ruby, see CONTRIBUTING.md). An optional last
# argument replaces the command, e.g. `rake 'check:ruby[3.4,bundle exec rspec spec/quality]'`;
# BUNDLE_GEMFILE is inherited, so a SimpleCov gemfile can be selected the same way as for rspec.
namespace :check do
  desc "Run the suite on JRuby in Docker (bin/check-ruby #{JRUBY_IMAGE}, C compiler installed first)"
  task :jruby, [:command] do |_task, args|
    sh({ 'CHECK_RUBY_SETUP' => JRUBY_SETUP }, 'bin/check-ruby', JRUBY_IMAGE, *[args[:command]].compact)
  end

  desc "Run the suite on TruffleRuby in Docker (bin/check-ruby #{TRUFFLERUBY_IMAGE})"
  task :truffleruby, [:command] do |_task, args|
    sh('bin/check-ruby', TRUFFLERUBY_IMAGE, *[args[:command]].compact)
  end

  desc 'Run the suite on another Ruby in Docker, as in rake check:ruby[2.7] (bin/check-ruby <version|image>)'
  task :ruby, %i[version command] do |_task, args|
    abort 'usage: rake check:ruby[<ruby-version|image>[,<command>]]' unless args[:version]

    sh('bin/check-ruby', args[:version], *[args[:command]].compact)
  end
end

task default: %i[spec rubocop suppressions typecheck yard reek flay flog debride audit build]
