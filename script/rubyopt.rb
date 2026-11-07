# Copyright (c) 2026 Vitalii Lazebnyi
# typed: strict
# frozen_string_literal: true

# Prints the RUBYOPT every Ruby command of this repository runs with (CI and script/check): all
# warnings (`-w`), the deprecation category and, on MRI >= 3.3 (older Rubies and the other
# engines have no such category), the performance category; plus script/upstream_warnings.rb,
# which drops the listed warnings of upstream gems. Runs on every supported Ruby, before
# Bundler.
flags = ['-w', '-W:deprecated']
flags << '-W:performance' if RUBY_ENGINE == 'ruby' && Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('3.3')
flags << "-r#{File.expand_path('upstream_warnings.rb', __dir__)}"
puts(flags.join(' '))
