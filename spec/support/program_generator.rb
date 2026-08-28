# typed: false
# frozen_string_literal: true

# Seeded generator of random, valid Ruby programs paired with the exact node table the AST
# resolver must derive from them (see ast_resolver_property_spec.rb). Every construct the
# resolver knows is composed at random — modules, classes (plain and compact), instance and
# singleton methods with self, constant and variable receivers, singleton classes opened on
# self, a constant, a local or an instance variable, Struct.new / Class.new / Module.new /
# Data.define blocks, define_method / define_singleton_method blocks — around transparent
# statements, comments and blank lines. Each construct occupies its own lines, indented two
# spaces per nesting level, so the expected line ranges are known while emitting; constructs
# Ruby forbids inside a method body (class definitions, constant assignments) are only emitted
# outside one.
class ProgramGenerator
  # A node the resolver must derive: [name, type, start_line, end_line].
  ExpectedNode = Struct.new(:name, :type, :start_line, :end_line)

  # The lexical scope a construct is emitted in: the resolver's context, whether a def here is
  # a singleton method (inside `class << …`) and whether a method body encloses it.
  Scope = Struct.new(:context, :singleton, :in_method) do
    def nest(name)
      context.empty? ? name : "#{context}::#{name}"
    end

    # A method defined at the top level belongs to Object (a plain `def`) or to `main` (a
    # singleton definition), the owners Ruby gives it.
    def method_name(name, singleton_method)
      owner = context.empty? ? top_level_owner(singleton_method) : context
      "#{owner}#{singleton_method ? '.' : '#'}#{name}"
    end

    def top_level_owner(singleton_method)
      singleton_method ? 'main' : 'Object'
    end

    def method_body
      Scope.new(context, singleton, true)
    end
  end

  # How many programs the property spec checks, and the first seed of its fixed sequence.
  PROGRAM_COUNT = 200
  DEFAULT_SEED = 20_260_428
  MAX_DEPTH = 3
  CONSTANT_NAMES = %w[Alpha Beta Gamma Delta].freeze
  METHOD_NAMES = %w[run stop reset parse].freeze
  BUILDERS = { 'Struct.new(:left, :right)' => 'Struct', 'Class.new' => 'Class',
               'Module.new' => 'Module', 'Data.define(:left)' => 'Data' }.freeze
  # Transparent statements, valid anywhere.
  STATEMENTS = ['value = 1', 'value ||= 2', 'puts value', '[1, 2].each { |item| item }',
                "if value\n  :yes\nelse\n  :no\nend", "begin\n  1\nrescue StandardError\n  2\nend",
                '# def class module end', ''].freeze
  # Transparent constant assignments, a syntax error inside a method body.
  CLASS_BODY_STATEMENTS = ['LIMIT = 3', 'PAIR = [1, 2].freeze'].freeze
  # Constructs Ruby rejects inside a method body.
  CLASS_BODY_KINDS = %i[module klass compact_class builder class_body_statement].freeze
  NESTABLE_KINDS = %i[instance_method self_method foreign_singleton lvar_singleton define_method
                      define_singleton_method sclass_self sclass_const sclass_lvar sclass_ivar].freeze

  # One emitter per construct kind; each appends lines and expected nodes through the
  # generator's primitives (emit_text, emit_block, emit_node) at the given nesting depth.
  module Constructs
    def emit_statement(_scope, depth)
      emit_text(depth, pick(STATEMENTS))
    end

    def emit_class_body_statement(_scope, depth)
      emit_text(depth, pick(CLASS_BODY_STATEMENTS))
    end

    def emit_module(scope, depth)
      name = pick(CONSTANT_NAMES)
      emit_node("module #{name}", scope.nest(name), 'Module', Scope.new(scope.nest(name), false, false), depth)
    end

    def emit_klass(scope, depth)
      name = pick(CONSTANT_NAMES)
      emit_node("class #{name}", scope.nest(name), 'Class', Scope.new(scope.nest(name), false, false), depth)
    end

    def emit_compact_class(scope, depth)
      name = "#{pick(CONSTANT_NAMES)}::#{pick(CONSTANT_NAMES)}"
      emit_node("class #{name}", scope.nest(name), 'Class', Scope.new(scope.nest(name), false, false), depth)
    end

    def emit_builder(scope, depth)
      builder, type = pick(BUILDERS.to_a)
      name = pick(CONSTANT_NAMES)
      emit_node("#{name} = #{builder} do", scope.nest(name), type, Scope.new(scope.nest(name), false, false), depth)
    end

    def emit_instance_method(scope, depth)
      name = pick(METHOD_NAMES)
      emit_node("def #{name}(input)", scope.method_name(name, scope.singleton), method_type(scope.singleton),
                scope.method_body, depth)
    end

    def emit_self_method(scope, depth)
      name = pick(METHOD_NAMES)
      emit_node("def self.#{name}", scope.method_name(name, true), 'Singleton Method', scope.method_body, depth)
    end

    def emit_foreign_singleton(scope, depth)
      receiver = pick(CONSTANT_NAMES)
      name = pick(METHOD_NAMES)
      emit_node("def #{receiver}.#{name}", "#{receiver}.#{name}", 'Singleton Method', scope.method_body, depth)
    end

    # A singleton definition on a local variable is attributed to the lexical context.
    def emit_lvar_singleton(scope, depth)
      emit_text(depth, 'holder = Object.new')
      name = pick(METHOD_NAMES)
      emit_node("def holder.#{name}", scope.method_name(name, true), 'Singleton Method', scope.method_body, depth)
    end

    # A block keeps the lexical scope (and its method-body restriction) for its children.
    def emit_define_method(scope, depth)
      name = pick(METHOD_NAMES)
      emit_node("define_method(:#{name}) do |input|", scope.method_name(name, scope.singleton),
                method_type(scope.singleton), scope, depth)
    end

    def emit_define_singleton_method(scope, depth)
      name = pick(METHOD_NAMES)
      emit_node("define_singleton_method(:#{name}) do", scope.method_name(name, true), 'Singleton Method', scope,
                depth)
    end

    def emit_sclass_self(scope, depth)
      emit_block('class << self', Scope.new(scope.context, true, scope.in_method), depth)
    end

    # `class << Const` names the constant itself, whatever the lexical context.
    def emit_sclass_const(scope, depth)
      receiver = pick(CONSTANT_NAMES)
      emit_block("class << #{receiver}", Scope.new(receiver, true, scope.in_method), depth)
    end

    def emit_sclass_lvar(scope, depth)
      emit_text(depth, 'target = Object.new')
      emit_block('class << target', Scope.new('target', true, scope.in_method), depth)
    end

    def emit_sclass_ivar(scope, depth)
      emit_block('class << @registry', Scope.new('@registry', true, scope.in_method), depth)
    end
  end

  include Constructs

  def initialize(seed)
    @random = Random.new(seed)
    @lines = []
    @expected = []
  end

  # @return [Array(String, Array<ExpectedNode>)] The program and its node table, root first.
  def generate
    top_level = Scope.new('', false, false)
    (1 + @random.rand(3)).times { emit_item(top_level, 0) }
    source = "#{@lines.join("\n")}\n"
    [source, [ExpectedNode.new('main', 'Root Script Scope', 1, @lines.size)] + @expected]
  end

  private

  def pick(candidates)
    candidates.fetch(@random.rand(candidates.size))
  end

  def emit_item(scope, depth)
    kinds = [:statement] * 3
    if depth < MAX_DEPTH
      kinds += NESTABLE_KINDS
      kinds += CLASS_BODY_KINDS unless scope.in_method
    end
    send(:"emit_#{pick(kinds)}", scope, depth)
  end

  def emit_text(depth, text)
    (text.empty? ? [''] : text.split("\n")).each do |line|
      @lines << (line.empty? ? '' : "#{'  ' * depth}#{line}")
    end
  end

  # A construct with a body: the opening line, one or two nested items and `end`.
  def emit_block(opening, inner_scope, depth)
    emit_text(depth, opening)
    (1 + @random.rand(2)).times { emit_item(inner_scope, depth + 1) }
    emit_text(depth, 'end')
  end

  # A construct the resolver reports as a node; recorded before its children (pre-order).
  def emit_node(opening, name, type, inner_scope, depth)
    start_line = @lines.size + 1
    position = @expected.size
    emit_block(opening, inner_scope, depth)
    @expected.insert(position, ExpectedNode.new(name, type, start_line, @lines.size))
  end

  def method_type(singleton)
    singleton ? 'Singleton Method' : 'Instance Method'
  end
end
