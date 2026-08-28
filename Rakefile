# typed: strict
# frozen_string_literal: true

require 'open3'
require 'tmpdir'
require 'rspec/core/rake_task'
require 'rubocop/rake_task'

# One-command local verification: `bundle exec rake` runs every gate CI enforces (see
# CONTRIBUTING.md). Advisory tooling lives behind `rake quality`; RBI regeneration behind `rake rbi`.

# sorbet-static ships MRI binaries for Linux and macOS only (see Gemfile).
SORBET_SUPPORTED = RUBY_ENGINE == 'ruby' && !Gem.win_platform?
# flay reports duplicated code with at least this mass (roughly, AST node count).
FLAY_MASS_THRESHOLD = 40
# flog scores above this on a single method mean it should be split up.
FLOG_METHOD_THRESHOLD = 35
# Docker images the `check:*` tasks run the suite in through bin/check-ruby. The official jruby
# image ships no C compiler, which prism (pulled in through rubocop-ast) needs to build, so the
# JRuby task installs one before `bundle install`.
JRUBY_IMAGE = 'jruby:9.4'
JRUBY_SETUP = 'apt-get update -qq && apt-get install -y -qq build-essential'
TRUFFLERUBY_IMAGE = 'ghcr.io/graalvm/truffleruby-community:latest'

# `-w` turns on Ruby's verbose warnings; spec/support/warnings.rb fails the suite on any warning
# raised by the gem's own files (dependencies may warn freely), exactly as the CI test jobs run.
RSpec::Core::RakeTask.new(:spec) { |task| task.ruby_opts = '-w' }
RuboCop::RakeTask.new(:rubocop)

desc 'Type-check lib/ with Sorbet at the strong level (`srb tc --typed strong`)'
task :typecheck do
  if SORBET_SUPPORTED
    sh 'bundle', 'exec', 'srb', 'tc', '--typed', 'strong'
  else
    warn 'Skipping Sorbet: sorbet-static is not available for this Ruby engine or platform.'
  end
end

desc 'Build the YARD documentation (warnings are fatal) and require 100% documentation coverage'
task :docs do
  sh 'bundle', 'exec', 'yardoc', '--fail-on-warning'
  stats, status = Open3.capture2('bundle', 'exec', 'yard', 'stats', '--list-undoc')
  puts stats
  abort 'yard stats failed' unless status.success?
  abort 'Documentation coverage is below 100% (see the list above)' unless stats.include?('100.00% documented')
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
    sh clean_env, 'ruby', '-e', 'require "simplecov-ai"; puts "Loaded simplecov-ai " + SimpleCov::Formatter::AIFormatter::VERSION'
  end
end

desc 'Regenerate the gem RBIs in sorbet/rbi/gems with tapioca (after changing dependencies)'
task :rbi do
  sh 'bundle', 'exec', 'bin/tapioca', 'gem'
end

desc 'Mutation testing of lib/ with mutant (see .mutant.yml); MUTANT_SINCE=<revision> limits it to touched subjects'
task :mutant do
  command = %w[bundle exec mutant run]
  command.push('--since', ENV.fetch('MUTANT_SINCE')) if ENV.key?('MUTANT_SINCE')
  sh(*command)
end

desc 'Advisory code-quality report: reek, flay, flog and debride (mirrors the CI quality job)'
task :quality do
  sh 'bundle', 'exec', 'reek', '--config', '.reek.yml', 'lib'

  flay_report, = Open3.capture2('bundle', 'exec', 'flay', '--mass', FLAY_MASS_THRESHOLD.to_s, 'lib')
  puts flay_report
  abort "flay: duplicated code with mass >= #{FLAY_MASS_THRESHOLD} found" unless flay_report.include?('= 0')

  flog_report, = Open3.capture2('bundle', 'exec', 'flog', '--all', '--methods-only', 'lib')
  puts flog_report
  hot_methods = flog_report.scan(%r{^\s*(\d+\.\d+): (\S+)\s+lib/})
                           .select { |score, _name| score.to_f > FLOG_METHOD_THRESHOLD }
                           .map(&:last)
  abort "flog: methods scoring above #{FLOG_METHOD_THRESHOLD}: #{hot_methods.join(', ')}" if hot_methods.any?

  # Informational only: the formatter's public API is invoked by SimpleCov, not from lib/.
  sh 'bundle', 'exec', 'debride', 'lib'
end

# `rake check:jruby`, `rake check:truffleruby` and `rake 'check:ruby[2.7]'` run the suite on another
# Ruby inside its official Docker image (bin/check-ruby, see CONTRIBUTING.md). An optional last
# argument replaces the command, e.g. `rake 'check:ruby[3.4,bundle exec rspec spec/quality]'`;
# BUNDLE_GEMFILE is inherited, so a SimpleCov gemfile can be selected the same way as for rspec.
namespace :check do
  desc 'Run the suite on JRuby 9.4 in Docker (bin/check-ruby jruby:9.4, C compiler installed first)'
  task :jruby, [:command] do |_task, args|
    sh({ 'CHECK_RUBY_SETUP' => JRUBY_SETUP }, 'bin/check-ruby', JRUBY_IMAGE, *[args[:command]].compact)
  end

  desc 'Run the suite on TruffleRuby in Docker (bin/check-ruby ghcr.io/graalvm/truffleruby-community:latest)'
  task :truffleruby, [:command] do |_task, args|
    sh('bin/check-ruby', TRUFFLERUBY_IMAGE, *[args[:command]].compact)
  end

  desc 'Run the suite on another Ruby in Docker, as in rake check:ruby[2.7] (bin/check-ruby <version|image>)'
  task :ruby, %i[version command] do |_task, args|
    abort 'usage: rake check:ruby[<ruby-version|image>[,<command>]]' unless args[:version]

    sh('bin/check-ruby', args[:version], *[args[:command]].compact)
  end
end

task default: %i[spec rubocop typecheck docs audit build]
