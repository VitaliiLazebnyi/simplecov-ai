# Copyright (c) 2026 Vitalii Lazebnyi
# typed: strict
# frozen_string_literal: true

# mutant selects the tests of a subject from the most specific scope that has any, walking
# outwards: `Foo::Bar#baz`, then everything described as `Foo::Bar`, then `Foo`, and so on. A
# spec described as `SimpleCov::Formatter::AIFormatter` therefore never runs for a subject
# inside MarkdownBuilder or ASTResolver, which have specs of their own. The whole-report specs
# are the strongest oracle the suite has, so they declare every scope that has a spec file as
# their subject (`mutant_expression: MutantScopes.spec_levels`) and join those selections.
# Scopes without a spec file are deliberately not declared: a declaration would open a new
# selection level holding only the whole-report specs and shadow the unit specs of the
# enclosing scope.
module MutantScopes
  extend T::Sig

  ROOT = SimpleCov::Formatter::AIFormatter
  private_constant(:ROOT)
  SPEC_DIR = T.let(File.expand_path('..', __dir__), String)
  private_constant(:SPEC_DIR)

  # @return [Array<String>] Every scope of the gem that has a spec file of its own, root first.
  sig { returns(T::Array[String]) }
  def self.spec_levels
    names = ObjectSpace.each_object(Module).filter_map(&:name)
    names.select! { |name| name.start_with?("#{ROOT.name}::") }
    names.sort!
    names.select! { |name| File.exist?(spec_path(name)) }
    [ROOT.name.to_s] + names
  end

  # The scopes whose behaviour the resultset fuzz exercises: report assembly and its containment.
  sig { returns(T::Array[String]) }
  def self.containment
    [ROOT, ROOT::MarkdownBuilder, ROOT::MarkdownBuilder::DecodeGuard].map { |scope| scope.name.to_s }
  end

  # The spec file describing a scope, by the snake-case path RuboCop's spec path cop expects.
  sig { params(name: String).returns(String) }
  def self.spec_path(name)
    segments =
      name.split('::').map do |segment|
        segment.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2').gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
      end
    File.join(SPEC_DIR, "#{segments.join('/')}_spec.rb")
  end
end
