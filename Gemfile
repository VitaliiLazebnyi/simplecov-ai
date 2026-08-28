# typed: strict
# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

# sorbet-static ships native binaries for MRI on Linux and macOS only, so the Sorbet toolchain
# (and the tooling built on it) cannot be installed on Windows, JRuby or TruffleRuby. Those
# platforms run the test suite only; everywhere else the bundle is identical to Linux/macOS.
sorbet_toolchain_supported = RUBY_ENGINE == 'ruby' && !Gem.win_platform?

if sorbet_toolchain_supported
  group :development do
    # prism is a default gem on Ruby >= 3.3 and only a transitive dependency elsewhere; it is
    # listed explicitly so `bin/tapioca gem` emits an RBI for it (tapioca only reflects direct
    # dependencies, and the simplecov RBI references `Prism::Visitor`).
    gem 'prism'
    gem 'rubocop-sorbet'
    gem 'sorbet', '~> 0.5'
    gem 'standard-sorbet'
    gem 'tapioca'
    gem 'yard-sorbet'
  end
end

# Advisory code-quality tooling behind `rake quality` (reek needs Ruby >= 3.1, so older Rubies
# skip the whole group instead of dragging in stale releases).
if sorbet_toolchain_supported && Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('3.1')
  group :quality do
    gem 'debride', '~> 1.15'
    gem 'flay', '~> 2.14'
    gem 'flog', '~> 4.9'
    gem 'reek', '~> 6.5'
  end
end
