# typed: false
# frozen_string_literal: true

# This file is a test fixture containing intentional branch deficits
# and edge cases for the coverage formatter. Applying standard linting rules alters
# the AST and destroys the specific branch coverage scenarios we are testing.
# Justification: Intentional branch deficits for AST test

module MetaprogrammingConstructs
  extend T::Sig

  # 1. define_method with a block
  define_method(:dynamic_instance_method) do |cond|
    if cond
      :dynamic_true
    else
      :dynamic_false
    end
  end

  # 2. define_singleton_method with a block
  define_singleton_method(:dynamic_class_method) do |val|
    case val
    when 1
      :singleton_case_one
    else
      :singleton_case_else
    end
  end

  # 3. class_eval with a block
  class_eval do
    sig { params(cond: Object).returns(Object) }
    def evaled_method(cond)
      cond ? :evaled_true : :evaled_false
    end
  end

  # 4. method_missing
  sig { params(method_name: Object, args: Object, block: Object).returns(Object) }
  def method_missing(method_name, *args, &block)
    if method_name.to_s.start_with?('magic_')
      :magic_handled
    else
      super
    end
  end

  sig { params(method_name: Object, include_private: Object).returns(Object) }
  def respond_to_missing?(method_name, include_private = false)
    method_name.to_s.start_with?('magic_') || super
  end

  # 5. Singleton class / Eigenclass
  class << self
    extend T::Sig

    # Justification: Deliberately testing AST branch parsing of unless/else
    # rubocop:disable Style/UnlessElse
    sig { params(cond: Object).returns(Object) }
    def eigen_method(cond)
      unless cond
        :eigen_false
      else
        :eigen_true
      end
    end
    # rubocop:enable Style/UnlessElse
  end
end

class MetaTarget
  include MetaprogrammingConstructs
end
# rubocop:enable all
