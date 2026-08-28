# typed: false
# frozen_string_literal: true

# Turns warnings emitted by the gem's own files into a failed run. Every warning Ruby prints
# passes through `Warning.warn` — with `-w` (the CI test jobs and `rake spec` set it) that
# includes verbose-mode diagnostics such as unused variables, ambiguous arguments and method
# redefinitions — and the ones whose text names a file under lib/ are recorded; dependencies
# stay free to warn. Deprecation warnings are switched on explicitly so a deprecated construct
# in lib/ is caught even without `-w`. The recorded warnings fail the suite from an
# `after(:suite)` hook, so every example still runs and the warnings are listed together.
class GemWarnings
  LIB_DIR = File.expand_path('../../lib', __dir__)

  # @return [Array<String>] The gem's warnings seen so far, in order.
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

  # @param message [Object] The warning text, recorded when it names a file of the gem.
  def record(message)
    text = message.to_s
    @collected << text if text.include?(LIB_DIR)
  end

  # @raise [RuntimeError] Listing every warning the gem emitted during the suite.
  def verify!
    return if @collected.empty?

    raise "The gem emitted #{@collected.size} warning(s) during the suite:\n#{@collected.join}"
  end
end
