# Copyright (c) 2026 Vitalii Lazebnyi
# typed: strict
# frozen_string_literal: true

# Seeded generator of random, valid Ruby programs paired with the exact node table the AST
# resolver must derive from them (see ast_resolver_property_spec.rb). Every construct the
# resolver knows is composed at random - modules, classes (plain and compact), instance and
# singleton methods with self, constant and variable receivers, singleton classes opened on
# self, a constant, a local or an instance variable, Struct.new / Class.new / Module.new /
# Data.define blocks, define_method / define_singleton_method blocks - around transparent
# statements, comments and blank lines. Each construct occupies its own lines, indented two
# spaces per nesting level, so the expected line ranges are known while emitting; constructs
# Ruby forbids inside a method body (class definitions, constant assignments) are only emitted
# outside one.
class ProgramGenerator
  extend T::Sig

  # The lexical scope a construct is emitted in: the resolver's context, whether a def here is
  # a singleton method (inside `class << ...`) and whether a method body encloses it.
  class Scope
    extend T::Sig

    sig { params(context: String, singleton: T::Boolean, in_method: T::Boolean).void }
    def initialize(context, singleton, in_method)
      @context = context
      @singleton = singleton
      @in_method = in_method
    end

    # @return [String] The resolver's context.
    sig { returns(String) }
    attr_reader :context

    # @return [Boolean] Whether a def here is a singleton method.
    sig { returns(T::Boolean) }
    attr_reader :singleton

    # @return [Boolean] Whether a method body encloses the scope.
    sig { returns(T::Boolean) }
    attr_reader :in_method

    # @param name [String] A constant defined in the scope.
    # @return [String] Its name as the resolver reports it.
    sig { params(name: String).returns(String) }
    def nest(name)
      context.empty? ? name : "#{context}::#{name}"
    end

    # A method defined at the top level belongs to Object (a plain `def`) or to `main` (a
    # singleton definition), the owners Ruby gives it.
    sig { params(name: String, singleton_method: T::Boolean).returns(String) }
    def method_name(name, singleton_method)
      owner = context.empty? ? top_level_owner(singleton_method) : context
      "#{owner}#{singleton_method ? '.' : '#'}#{name}"
    end

    # @return [Scope] The scope of a method body defined here.
    sig { returns(Scope) }
    def method_body
      Scope.new(context, singleton, true)
    end

    private

    sig { params(singleton_method: T::Boolean).returns(String) }
    def top_level_owner(singleton_method)
      singleton_method ? 'main' : 'Object'
    end
  end
  private_constant(:Scope)

  # The emitters of the constructs, one per kind; each appends lines and expected nodes through
  # the generator's primitives (emit_text, emit_block, emit_node) at the given nesting depth. A
  # transparent statement is valid anywhere.
  class Constructs
    extend T::Sig

    CONSTANT_NAMES = %w[Alpha Beta Gamma Delta].freeze
    private_constant(:CONSTANT_NAMES)
    METHOD_NAMES = %w[run stop reset parse].freeze
    private_constant(:METHOD_NAMES)
    BUILDERS = T.let(
      {
        'Struct.new(:left, :right)' => 'Struct',
        'Class.new' => 'Class',
        'Module.new' => 'Module',
        'Data.define(:left)' => 'Data'
      }.freeze,
      T::Hash[String, String]
    )
    private_constant(:BUILDERS)
    # Transparent statements, valid anywhere.
    STATEMENTS = [
      'value = 1',
      'value ||= 2',
      'puts value',
      '[1, 2].each { |item| item }',
      "if value\n  :yes\nelse\n  :no\nend",
      "begin\n  1\nrescue StandardError\n  2\nend",
      '# def class module end',
      ''
    ].freeze
    private_constant(:STATEMENTS)
    # Transparent constant assignments, a syntax error inside a method body.
    CLASS_BODY_STATEMENTS = ['LIMIT = 3', 'PAIR = [1, 2].freeze'].freeze
    private_constant(:CLASS_BODY_STATEMENTS)

    sig { params(generator: ProgramGenerator).void }
    def initialize(generator)
      @generator = generator
    end

    sig { params(_scope: Scope, depth: Integer).void }
    def emit_statement(_scope, depth)
      @generator.emit_text(depth, @generator.pick(STATEMENTS))
    end
  end
  private_constant(:Constructs)

  # The constructs Ruby rejects inside a method body: namespaces, builder blocks and constant
  # assignments.
  class DefinitionConstructs < Constructs
    sig { params(_scope: Scope, depth: Integer).void }
    def emit_class_body_statement(_scope, depth)
      @generator.emit_text(depth, @generator.pick(CLASS_BODY_STATEMENTS))
    end

    sig { params(scope: Scope, depth: Integer).void }
    def emit_module(scope, depth)
      name = @generator.pick(CONSTANT_NAMES)
      @generator.emit_node(
        "module #{name}",
        scope.nest(name),
        'Module',
        Scope.new(scope.nest(name), false, false),
        depth
      )
    end

    sig { params(scope: Scope, depth: Integer).void }
    def emit_klass(scope, depth)
      name = @generator.pick(CONSTANT_NAMES)
      @generator.emit_node("class #{name}", scope.nest(name), 'Class', Scope.new(scope.nest(name), false, false), depth)
    end

    sig { params(scope: Scope, depth: Integer).void }
    def emit_compact_class(scope, depth)
      name = "#{@generator.pick(CONSTANT_NAMES)}::#{@generator.pick(CONSTANT_NAMES)}"
      @generator.emit_node("class #{name}", scope.nest(name), 'Class', Scope.new(scope.nest(name), false, false), depth)
    end

    sig { params(scope: Scope, depth: Integer).void }
    def emit_builder(scope, depth)
      builder, type = @generator.pick(BUILDERS.to_a)
      name = @generator.pick(CONSTANT_NAMES)
      @generator.emit_node(
        "#{name} = #{builder} do",
        scope.nest(name),
        type,
        Scope.new(scope.nest(name), false, false),
        depth
      )
    end
  end
  private_constant(:DefinitionConstructs)

  # Methods and singleton classes, valid at any depth.
  class MethodConstructs < Constructs
    sig { params(scope: Scope, depth: Integer).void }
    def emit_instance_method(scope, depth)
      name = @generator.pick(METHOD_NAMES)
      @generator.emit_node(
        "def #{name}(input)",
        scope.method_name(name, scope.singleton),
        @generator.method_type(scope.singleton),
        scope.method_body,
        depth
      )
    end

    sig { params(scope: Scope, depth: Integer).void }
    def emit_self_method(scope, depth)
      name = @generator.pick(METHOD_NAMES)
      @generator.emit_node(
        "def self.#{name}",
        scope.method_name(name, true),
        'Singleton Method',
        scope.method_body,
        depth
      )
    end

    sig { params(scope: Scope, depth: Integer).void }
    def emit_foreign_singleton(scope, depth)
      receiver = @generator.pick(CONSTANT_NAMES)
      name = @generator.pick(METHOD_NAMES)
      @generator.emit_node(
        "def #{receiver}.#{name}",
        "#{receiver}.#{name}",
        'Singleton Method',
        scope.method_body,
        depth
      )
    end

    # A singleton definition on a local variable is attributed to the lexical context.
    sig { params(scope: Scope, depth: Integer).void }
    def emit_lvar_singleton(scope, depth)
      @generator.emit_text(depth, 'holder = Object.new')
      name = @generator.pick(METHOD_NAMES)
      @generator.emit_node(
        "def holder.#{name}",
        scope.method_name(name, true),
        'Singleton Method',
        scope.method_body,
        depth
      )
    end

    # A block keeps the lexical scope (and its method-body restriction) for its children.
    sig { params(scope: Scope, depth: Integer).void }
    def emit_define_method(scope, depth)
      name = @generator.pick(METHOD_NAMES)
      @generator.emit_node(
        "define_method(:#{name}) do |input|",
        scope.method_name(name, scope.singleton),
        @generator.method_type(scope.singleton),
        scope,
        depth
      )
    end

    sig { params(scope: Scope, depth: Integer).void }
    def emit_define_singleton_method(scope, depth)
      name = @generator.pick(METHOD_NAMES)
      @generator.emit_node(
        "define_singleton_method(:#{name}) do",
        scope.method_name(name, true),
        'Singleton Method',
        scope,
        depth
      )
    end

    sig { params(scope: Scope, depth: Integer).void }
    def emit_sclass_self(scope, depth)
      @generator.emit_block('class << self', Scope.new(scope.context, true, scope.in_method), depth)
    end

    # `class << Const` names the constant itself, whatever the lexical context.
    sig { params(scope: Scope, depth: Integer).void }
    def emit_sclass_const(scope, depth)
      receiver = @generator.pick(CONSTANT_NAMES)
      @generator.emit_block("class << #{receiver}", Scope.new(receiver, true, scope.in_method), depth)
    end

    sig { params(scope: Scope, depth: Integer).void }
    def emit_sclass_lvar(scope, depth)
      @generator.emit_text(depth, 'target = Object.new')
      @generator.emit_block('class << target', Scope.new('target', true, scope.in_method), depth)
    end

    sig { params(scope: Scope, depth: Integer).void }
    def emit_sclass_ivar(scope, depth)
      @generator.emit_block('class << @registry', Scope.new('@registry', true, scope.in_method), depth)
    end
  end
  private_constant(:MethodConstructs)
end

class ProgramGenerator
  # How many programs the property spec checks, and the first seed of its fixed sequence.
  PROGRAM_COUNT = 200
  public_constant(:PROGRAM_COUNT)
  DEFAULT_SEED = 20_260_428
  public_constant(:DEFAULT_SEED)
  MAX_DEPTH = 3
  private_constant(:MAX_DEPTH)
  # Constructs Ruby rejects inside a method body.
  CLASS_BODY_KINDS = %i[module klass compact_class builder class_body_statement].freeze
  private_constant(:CLASS_BODY_KINDS)
  NESTABLE_KINDS = %i[
    instance_method
    self_method
    foreign_singleton
    lvar_singleton
    define_method
    define_singleton_method
    sclass_self
    sclass_const
    sclass_lvar
    sclass_ivar
      ].freeze
  private_constant(:NESTABLE_KINDS)

  sig { params(seed: Integer).void }
  def initialize(seed)
    @random = T.let(Random.new(seed), Random)
    @lines = T.let([], T::Array[String])
    @expected = T.let([], T::Array[[String, String, Integer, Integer]])
    @definitions = T.let(DefinitionConstructs.new(self), DefinitionConstructs)
    @methods = T.let(MethodConstructs.new(self), MethodConstructs)
  end

  # @return [Array(String, Array<Array(String, String, Integer, Integer)>)] The program and its
  #   node table (name, type, start line, end line), root first.
  sig { returns([String, T::Array[[String, String, Integer, Integer]]]) }
  def generate
    top_level = Scope.new('', false, false)
    (@random.rand(3) + 1).times { emit_item(top_level, 0) }
    source = "#{@lines.join("\n")}\n"
    [source, [['main', 'Root Script Scope', 1, @lines.size]] + @expected]
  end

  # The primitives the constructs emit through.

  # @param candidates [Array] The choices.
  # @return [Object] One of them, drawn from the seeded sequence.
  sig do
    type_parameters(:Candidate)
      .params(candidates: T::Array[T.type_parameter(:Candidate)])
      .returns(T.type_parameter(:Candidate))
  end
  def pick(candidates)
    candidates.fetch(@random.rand(candidates.size))
  end

  # Appends `text`, indented to `depth`, line by line.
  sig { params(depth: Integer, text: String).void }
  def emit_text(depth, text)
    (text.empty? ? [''] : text.split("\n")).each do |line|
      @lines << (line.empty? ? '' : "#{'  ' * depth}#{line}")
    end
  end

  # A construct with a body: the opening line, one or two nested items and `end`.
  sig { params(opening: String, inner_scope: Scope, depth: Integer).void }
  def emit_block(opening, inner_scope, depth)
    emit_text(depth, opening)
    (@random.rand(2) + 1).times { emit_item(inner_scope, depth + 1) }
    emit_text(depth, 'end')
  end

  # A construct the resolver reports as a node; recorded before its children (pre-order).
  sig { params(opening: String, name: String, type: String, inner_scope: Scope, depth: Integer).void }
  def emit_node(opening, name, type, inner_scope, depth)
    start_line = @lines.size + 1
    position = @expected.size
    emit_block(opening, inner_scope, depth)
    @expected.insert(position, [name, type, start_line, @lines.size])
  end

  # @param singleton [Boolean] Whether a plain `def` defines a singleton method here.
  # @return [String] The node type of a method defined by a plain `def`.
  sig { params(singleton: T::Boolean).returns(String) }
  def method_type(singleton)
    singleton ? 'Singleton Method' : 'Instance Method'
  end

  private

  # One construct, drawn at random from those valid at this depth and in this scope.
  sig { params(scope: Scope, depth: Integer).void }
  def emit_item(scope, depth)
    kinds = [:statement] * 3
    if depth < MAX_DEPTH
      kinds += NESTABLE_KINDS
      kinds += CLASS_BODY_KINDS unless scope.in_method
    end
    kind = pick(kinds)
    emitters = CLASS_BODY_KINDS.include?(kind) ? @definitions : @methods
    emitters.public_send(:"emit_#{kind}", scope, depth)
  end
end
