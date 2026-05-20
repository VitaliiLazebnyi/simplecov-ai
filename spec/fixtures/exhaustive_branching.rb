# typed: false
# frozen_string_literal: true

# This file is a test fixture containing intentional branch deficits
# and edge cases for the coverage formatter. Applying standard linting rules alters
# the AST and destroys the specific branch coverage scenarios we are testing.
# Justification: Intentional branch deficits for AST test

module ExhaustiveBranching
  extend T::Sig

  sig { params(cond: Object).returns(Object) }
  def self.test_if_else(cond)
    if cond
      :if_true
    else
      :if_false
    end
  end

  # Justification: Deliberately testing AST branch parsing of unless/else
  # rubocop:disable Style/UnlessElse
  sig { params(cond: Object).returns(Object) }
  def self.test_unless_else(cond)
    unless cond
      :unless_true
    else
      :unless_false
    end
  end
  # rubocop:enable Style/UnlessElse

  sig { params(cond: Object).returns(Object) }
  def self.test_ternary(cond)
    cond ? :ternary_true : :ternary_false
  end

  sig { params(val: Object).returns(Object) }
  def self.test_case_when(val)
    case val
    when 1
      :case_one
    when 2
      :case_two
    else
      :case_else
    end
  end

  sig { params(obj: Object).returns(Object) }
  def self.test_safe_nav(obj)
    obj&.name
  end
end

module ExhaustiveBranching
  extend T::Sig

  sig { params(arg_a: Object, arg_b: Object).returns(Object) }
  def self.test_logical_and(arg_a, arg_b)
    arg_a && arg_b
  end

  sig { params(arg_a: Object, arg_b: Object).returns(Object) }
  def self.test_logical_or(arg_a, arg_b)
    arg_a || arg_b
  end

  sig { params(arg_a: Object, arg_b: Object).returns(Object) }
  def self.test_logical_or_assign(arg_a, arg_b)
    arg_a ||= arg_b
    arg_a
  end

  sig { params(arg_a: Object, arg_b: Object).returns(Object) }
  def self.test_logical_and_assign(arg_a, arg_b)
    arg_a &&= arg_b
    arg_a
  end

  # Justification: Deliberately testing AST branch parsing of inline while/until loops with break
  # rubocop:disable Lint/UnreachableLoop
  sig { params(cond: Object).returns(Object) }
  def self.test_while_loop(cond)
    break :while_break while cond
  end

  sig { params(cond: Object).returns(Object) }
  def self.test_until_loop(cond)
    break :until_break until cond
  end
  # rubocop:enable Lint/UnreachableLoop

  sig { params(val: Object).returns(Object) }
  def self.test_pattern_matching(val)
    case val
    in 1
      :pattern_one
    in 2
      :pattern_two
    else
      :pattern_else
    end
  end

  sig { params(cond: Object).returns(Object) }
  def self.test_inline_if(cond)
    :inline_yes if cond
  end

  sig { params(val: Object).returns(Object) }
  def self.test_multiple_when(val)
    case val
    when 1, 2, 3
      :multiple_when_match
    else
      :multiple_when_else
    end
  end

  sig { params(val: Object).returns(Object) }
  def self.test_one_line_pattern(val)
    val in { a: 1 }
  end

  sig { params(obj: Object).returns(Object) }
  def self.test_chained_safe_nav(obj)
    obj&.a&.b
  end

  sig { returns(Object) }
  def self.test_inline_rescue
    raise 'error'
  rescue StandardError
    :rescued
  end

  sig { params(raise_err: Object).returns(Object) }
  def self.test_begin_rescue(raise_err)
    raise 'error' if raise_err

    :success
  rescue StandardError
    :rescued
  else
    :no_error
  end
end
