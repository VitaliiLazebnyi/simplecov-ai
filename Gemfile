# Copyright (c) 2026 Vitalii Lazebnyi
# typed: strict
# frozen_string_literal: true

source 'https://rubygems.org'

gemspec
eval_gemfile 'gemfiles/test.gemfile'

# The development tooling - lint, type checking, documentation, smell, duplication, audit and
# mutation gates - runs on the lockfile Ruby (.ruby-version) only. Its newest releases need
# Ruby >= 3.3 (rubocop-sorbet 0.17, tapioca 0.20, mutant 0.17, reek 6.6), and sorbet-static ships
# native binaries for MRI on Linux and macOS only, so the older Rubies, Windows, JRuby and
# TruffleRuby resolve the test bundle (gemfiles/test.gemfile) and nothing else.
tooling_supported = RUBY_ENGINE == 'ruby' && !Gem.win_platform? &&
  Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('3.3')

if tooling_supported
  group :development do
    # Audits the locked gems against the Ruby Advisory Database (`rake audit`).
    gem 'bundler-audit', '~> 0.9.3'
    # Finds methods without a caller (`rake debride`).
    gem 'debride', '~> 1.15'
    # Finds structural duplication (`rake flay`).
    gem 'flay', '~> 2.14'
    # Scores method complexity (`rake flog`).
    gem 'flog', '~> 4.9'
    # Mutation testing (`rake mutant`).
    gem 'mutant-rspec', '~> 0.17.1'
    # Code smell detection (`rake reek`).
    gem 'reek', '~> 6.6'
    # Static analysis and style (`rake rubocop`), with the plugins below.
    gem 'rubocop', '~> 1.92'
    # Lints the Ruby snippets of the Markdown files.
    gem 'rubocop-md', '~> 3.0'
    # Gem packaging cops.
    gem 'rubocop-packaging', '~> 0.6'
    # Performance cops.
    gem 'rubocop-performance', '~> 1.27'
    # Rakefile cops.
    gem 'rubocop-rake', '~> 0.7'
    # RSpec cops.
    gem 'rubocop-rspec', '~> 3.10'
    # Sorbet cops.
    gem 'rubocop-sorbet', '~> 0.17'
    # Thread-safety cops.
    gem 'rubocop-thread_safety', '~> 0.8'
    # Checks YARD tags against the code they document.
    gem 'rubocop-yard', '~> 1.3'
    # The type checker (`rake typecheck`).
    gem 'sorbet', '~> 0.6'
    # Generates the gem RBIs Sorbet checks against.
    gem 'tapioca', '~> 0.20'
    # API documentation, required to be complete (`rake yard`).
    gem 'yard', '~> 0.9.45'
    # Reads Sorbet signatures into the YARD documentation.
    gem 'yard-sorbet', '~> 0.9'
  end
end
