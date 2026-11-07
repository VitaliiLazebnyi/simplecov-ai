# Copyright (c) 2026 Vitalii Lazebnyi
# typed: true
# frozen_string_literal: true

# Every Ruby command of this repository runs with all warnings on (script/rubyopt.rb), and the
# warning gate of every workflow fails on any warning in a log. With them on, a few of the
# newest releases of the development tools, and SimpleCov, warn about their own code; `rake
# outdated` verifies that each of those gems is at its newest release. Those warnings are
# upstream's: they cannot be fixed in this repository.
#
# RUBYOPT loads this file (`-r`, before Bundler, so it is plain Ruby that runs on every
# supported Ruby). It drops exactly the warnings listed below, each matched by the gem, the
# file and the message; every other warning, from any gem or from this repository, is printed
# as usual and fails the build. An entry whose gem is fixed upstream must be removed.
module UpstreamWarnings
  # The pattern of the first line of a warning `file` (a path below a gems directory, starting
  # with the gem's name and version) emits.
  #
  # @param file [String] The gem file, e.g. `yard-0.9.45/lib/yard/cli/yardoc.rb`.
  # @param message [String] The source of a regular expression matching the message after
  #   `warning: `.
  # @return [Regexp] The pattern.
  def self.upstream(file, message)
    Regexp.new("/gems/#{file}:\\d+: warning: #{message}\\z")
  end

  # The dropped warnings, each with the gem release that emits it.
  KNOWN = {
    # rubocop-md parses the Markdown files with kramdown: a regular expression of its parser.
    upstream('kramdown-2\.5\.2/lib/kramdown/parser/base\.rb', 'character class has duplicated range: .*') =>
      'kramdown 2.5.2',
    # rubocop-yard parses the YARD tags with YARD, whose types_explainer.rb defines #create_type twice.
    upstream('yard-0\.9\.45/lib/yard/tags/types_explainer\.rb', 'method redefined; discarding old create_type') =>
      'yard 0.9.45',
    # `yardoc` and `yard stats` set the process's default encodings and use a redundant regular
    # expression, and YARD's templates add instance variables to Object in many orders.
    upstream('yard-0\.9\.45/lib/yard/cli/yardoc\.rb', 'setting Encoding\.default_(internal|external)') =>
      'yard 0.9.45',
    upstream(
      'yard-0\.9\.45/lib/yard/templates/helpers/markup/hybrid_markdown\.rb',
      'character class has duplicated range'
    ) => 'yard 0.9.45',
    upstream('yard-0\.9\.45/lib/yard/templates/template\.rb', 'The class Object reached \d+ shape variations, .*') =>
      'yard 0.9.45',
    # yard-sorbet, loaded as a YARD plugin, requires yard.rb while yard.rb is still loading.
    %r{warning: loading in progress, circular require considered harmful - \S+/gems/yard-0\.9\.45/lib/yard\.rb\z} =>
      'yard-sorbet 0.9.0',
    # `tapioca gem`: Tapioca redefines Kernel#exit and #abort on purpose.
    upstream('tapioca-0\.20\.0/lib/tapioca/runtime/helpers\.rb', 'method redefined; discarding old (exit|abort)') =>
      'tapioca 0.20.0',
    # `bundler-audit check`: bundler-audit adds Thor#say_error for the Thor versions that lack it.
    upstream(
      'bundler-audit-0\.9\.3/lib/bundler/audit/cli/thor_ext/shell/basic/say_error\.rb',
      'method redefined; discarding old say_error'
    ) => 'bundler-audit 0.9.3',
    # SimpleCov memoizes the instance variables of a SourceFile lazily, each on first use, so the
    # suite (which builds SourceFiles and reads them in many orders) gives the class many shapes.
    upstream(
      'simplecov-[\d.]+/lib/simplecov/source_file\.rb',
      'The class SimpleCov::SourceFile reached \d+ shape variations, .*'
    ) => 'simplecov'
  }.freeze
  public_constant(:KNOWN)

  # Whether a warning is one of the known upstream warnings. A warning can span several lines (a
  # backtrace, or the location of a previous definition); its first line identifies it.
  #
  # @param message [Object] The text passed to `Warning.warn`.
  # @return [Boolean] Whether the warning is dropped.
  def self.known?(message)
    first_line = message.to_s.lines.first.to_s.chomp
    KNOWN.keys.any? { |pattern| pattern.match?(first_line) }
  end

  # Prints the warning unless it is a known upstream warning. Ruby 2.7 passes only the message,
  # Ruby >= 3.0 adds `category:`.
  #
  # @param message [String] The warning.
  # @param options [Hash] The warning's category, on Ruby >= 3.0.
  # @return [void]
  def warn(message, **options)
    return if UpstreamWarnings.known?(message)

    super
  end
end

Warning.singleton_class.prepend(UpstreamWarnings)
