# typed: false
# frozen_string_literal: true

# Fixture for the AST resolver. It is parsed, never loaded: ast_resolver_spec.rb asserts the
# exact node table (name, type, first and last line) the resolver derives from it, so line
# numbers matter — append new constructs at the end rather than inserting them.
# Justification: the constructs below intentionally use the exact shapes under test.

# simplecov:disable
TOP_LEVEL_SETTING = :bypassed_at_root
# simplecov:enable

# Constant assignment shapes that carry no block value (and once crashed the resolver).
module Versioned
  MAJOR, MINOR, *OTHER = '1.2.3'.split('.')
  DEFAULT ||= 'stable'
  ORDERINGS = [REQUIRE_ORDER = 0, PERMUTE = 1].freeze

  def version
    [MAJOR, MINOR].join('.')
  end
end

Mixin = Module.new do
  def helper
    :helped
  end
end

Point = Struct.new(:x, :y) do
  def distance
    Math.sqrt((x * x) + (y * y))
  end
end

PAIR = Struct.new(:left, :right) { _1 }

# Dynamically defined methods.
class Dynamic
  define_method(:literal_symbol) do |flag|
    flag ? :on : :off
  end

  define_method(:braced) { :braced }

  define_method(:numbered) { _1 }

  define_singleton_method(:build) do
    new
  end

  computed = :computed_name
  define_method(computed) { :unnamed }

  klass = Class.new
  klass.define_method(:foreign) { :foreign }

  [1].each do |item|
    item
  end

  class << self
    define_method(:singleton_scoped) { :scoped }
  end
end

# A block attached to `super` rather than to a method call.
class Delegator
  def relay
    super do |value|
      value
    end
  end
end

# Singleton classes opened on receivers other than `self`.
class Registrar
  handler = Object.new
  class << handler
    def assist
      :assisted
    end
  end

  class << Delegator
    def make
      new
    end
  end

  class << Object.new
    def opaque
      :opaque
    end
  end

  def initialize
    @store = Object.new
  end

  def install
    class << @store
      def lookup
        :found
      end
    end
  end

  class << self
    def registered
      :yes
    end
  end
end
