# Copyright (c) 2026 Vitalii Lazebnyi
# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'

# Turns every warning emitted while the suite runs into a failed run, whichever file - the gem's,
# a spec's or a dependency's - it comes from. Every warning Ruby prints passes through
# `Warning.warn` - with `-w` (the CI test jobs and `rake spec` set it) that includes verbose-mode
# diagnostics such as unused variables, ambiguous arguments and method redefinitions - and is
# recorded. The deprecation category is switched on explicitly so deprecations are caught even
# without `-w`. (Ruby's opt-in performance category stays off: SimpleCov::SourceFile memoizes its
# instance variables lazily, so any suite building SourceFiles trips its object-shape warning.) The
# recorded warnings fail the suite from an
# `after(:suite)` hook, so every example still runs and the warnings are listed together. (The
# CI warning gate additionally fails on any warning in a job's log.)
class GemWarnings
  extend T::Sig

  # Text that marks a warning: Ruby's own (`file:line: warning: ...`) and the deprecation
  # notices of libraries. A plain `Kernel#warn` notice - such as the formatter's own "could not
  # be written" report, which examples capture and assert on - is not a warning.
  WARNING_TEXT = /warning:|deprecat/i.freeze
  private_constant(:WARNING_TEXT)
  # Every message on its way to the real STDERR that `Warning.warn` was handed since the hook was
  # installed, in order. A warning an example captures (RSpec's `output(...).to_stderr` swaps
  # `$stderr` for a StringIO for the duration) is that example's assertion, not queued.
  RECEIVED = Thread::Queue.new
  private_constant(:RECEIVED)

  # Raised after the suite when any warning was emitted.
  class Emitted < StandardError; end

  # Prepended to `Warning`'s singleton class: hands every message to {GemWarnings} before Ruby
  # prints it (Ruby 2.7 passes only the message, Ruby >= 3.0 adds `category:`).
  module Hook
    extend T::Sig

    # @param message [String] The warning.
    # @param options [Hash{Symbol => Symbol, nil}] `category:` on Ruby >= 3.0.
    # @return [void]
    sig { params(message: String, options: T.nilable(Symbol)).void }
    def warn(message, **options)
      RECEIVED << message if $stderr.is_a?(IO)
      options.empty? ? super(message) : super
    end
  end
  private_constant(:Hook)

  sig { void }
  def initialize
    @collected = T.let([], T::Array[String])
  end

  # @return [Array<String>] The warnings seen so far, in order.
  sig { returns(T::Array[String]) }
  attr_reader :collected

  # Hooks `Warning.warn` so every warning is recorded here before Ruby prints it.
  #
  # @return [void]
  sig { void }
  def install!
    Warning.singleton_class.prepend(Hook)
    Warning[:deprecated] = true
  end

  # Records the warnings queued by the hook since the last call, except the upstream warnings
  # script/upstream_warnings.rb drops (loaded through RUBYOPT).
  #
  # @return [void]
  sig { void }
  def record
    Array.new(RECEIVED.size) { String(RECEIVED.pop) }
      .each do |text|
      next if defined?(UpstreamWarnings) && UpstreamWarnings.known?(text)

      @collected << text if text.match?(WARNING_TEXT)
    end
  end

  # @raise [Emitted] Listing every warning emitted during the suite.
  # @return [void]
  sig { void }
  def verify!
    record
    return if @collected.empty?

    raise(Emitted, "#{@collected.size} warning(s) were emitted during the suite:\n#{@collected.join}")
  end
end
