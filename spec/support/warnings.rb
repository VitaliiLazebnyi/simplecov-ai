# typed: false
# frozen_string_literal: true

# Turns every warning emitted while the suite runs into a failed run, whichever file — the gem's,
# a spec's or a dependency's — it comes from. Every warning Ruby prints passes through
# `Warning.warn` — with `-w` (the CI test jobs and `rake spec` set it) that includes verbose-mode
# diagnostics such as unused variables, ambiguous arguments and method redefinitions — and is
# recorded. The deprecation category is switched on explicitly so deprecations are caught even
# without `-w`. (Ruby's opt-in performance category stays off: SimpleCov::SourceFile memoizes its
# instance variables lazily, so any suite building SourceFiles trips its object-shape warning.) The recorded warnings fail the suite from an
# `after(:suite)` hook, so every example still runs and the warnings are listed together. (The
# CI warning gate additionally fails on any warning in a job's log.)
class GemWarnings
  # Text that marks a warning: Ruby's own (`file:line: warning: ...`) and the deprecation
  # notices of libraries. A plain `Kernel#warn` notice — such as the formatter's own "could not
  # be written" report, which examples capture and assert on — is not a warning.
  WARNING_TEXT = /warning:|deprecat/i.freeze

  # @return [Array<String>] The warnings seen so far, in order.
  attr_reader :collected

  def initialize
    @collected = []
  end

  # Hooks `Warning.warn` (Ruby 2.7 passes only the message, Ruby >= 3.0 adds `category:`) so
  # every warning is recorded here before Ruby prints it.
  def install!
    collector = self
    Warning.singleton_class.prepend(Module.new do
      define_method(:warn) do |message, **options|
        collector.record(message)
        options.empty? ? super(message) : super(message, **options)
      end
    end)
    Warning[:deprecated] = true
  end

  # @param message [Object] The text passed to `Warning.warn`, recorded when it is a warning on
  #   its way to the real STDERR. A warning an example captures (RSpec's `output(...).to_stderr`
  #   swaps `$stderr` for a StringIO for the duration) is that example's assertion.
  def record(message)
    text = message.to_s
    @collected << text if text.match?(WARNING_TEXT) && $stderr.is_a?(IO)
  end

  # @raise [RuntimeError] Listing every warning emitted during the suite.
  def verify!
    return if @collected.empty?

    raise "#{@collected.size} warning(s) were emitted during the suite:\n#{@collected.join}"
  end
end
