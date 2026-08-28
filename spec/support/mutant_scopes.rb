# typed: false
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
  ROOT = SimpleCov::Formatter::AIFormatter
  SPEC_DIR = File.expand_path('..', __dir__)

  # @return [Array<String>] Every scope of the gem that has a spec file of its own, root first.
  def self.spec_levels
    nested = ObjectSpace.each_object(Module).select { |scope| scope.name.to_s.start_with?("#{ROOT.name}::") }
    [ROOT.name] + nested.map(&:name).sort.select { |name| File.exist?(spec_path(name)) }
  end

  # The scopes whose behaviour the resultset fuzz exercises: report assembly and its containment.
  def self.containment
    [ROOT, ROOT::MarkdownBuilder, ROOT::MarkdownBuilder::DecodeGuard].map(&:name)
  end

  # The spec file describing a scope, by the snake-case path RuboCop's spec path cop expects.
  def self.spec_path(name)
    segments = name.split('::').map do |segment|
      segment.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2').gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
    end
    File.join(SPEC_DIR, "#{segments.join('/')}_spec.rb")
  end
end
