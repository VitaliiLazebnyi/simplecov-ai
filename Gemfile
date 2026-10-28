# typed: strict
# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

# The development tooling — lint, type checking, documentation, smell, duplication, audit and
# mutation gates — runs on the lockfile Ruby (.ruby-version) only. Its newest releases need
# Ruby >= 3.3 (rubocop-sorbet 0.17, tapioca 0.20, mutant 0.17, reek 6.6), and sorbet-static ships
# native binaries for MRI on Linux and macOS only, so the older Rubies, Windows, JRuby and
# TruffleRuby resolve the test bundle declared in the gemspec and nothing else.
tooling_supported = RUBY_ENGINE == 'ruby' && !Gem.win_platform? &&
                    Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('3.3')

if tooling_supported
  group :development do
    gem 'bundler-audit', '~> 0.9.3'
    gem 'debride', '~> 1.15'
    gem 'flay', '~> 2.14'
    gem 'flog', '~> 4.9'
    gem 'mutant-rspec', '~> 0.17.1'
    gem 'reek', '~> 6.6'
    gem 'rubocop', '~> 1.92'
    gem 'rubocop-md', '~> 2.0'
    gem 'rubocop-packaging', '~> 0.6'
    gem 'rubocop-performance', '~> 1.27'
    gem 'rubocop-rake', '~> 0.7'
    gem 'rubocop-rspec', '~> 3.10'
    gem 'rubocop-sorbet', '~> 0.17'
    gem 'rubocop-thread_safety', '~> 0.8'
    gem 'sorbet', '~> 0.6'
    gem 'tapioca', '~> 0.20'
    gem 'yard', '~> 0.9.45'
    gem 'yard-sorbet', '~> 0.9'
  end
end
