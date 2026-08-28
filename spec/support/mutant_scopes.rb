# typed: false
# frozen_string_literal: true

# mutant runs, for each subject, the tests of the most specific scope that has any: a spec
# described as `SimpleCov::Formatter::AIFormatter` therefore never runs for a subject inside
# MarkdownBuilder or ASTResolver, which have specs of their own. The whole-report specs are the
# strongest oracle the suite has, so they declare every scope of the gem as their subject
# (`mutant_expression: MutantScopes.all`) and take part in every subject's selection.
module MutantScopes
  ROOT = SimpleCov::Formatter::AIFormatter

  # @return [Array<String>] Every named module and class of the gem, root first.
  def self.all
    nested = ObjectSpace.each_object(Module).select { |scope| scope.name.to_s.start_with?("#{ROOT.name}::") }
    [ROOT.name] + nested.map(&:name).sort
  end

  # The scopes whose behaviour the resultset fuzz exercises: report assembly and its containment.
  def self.containment
    [ROOT, ROOT::MarkdownBuilder, ROOT::MarkdownBuilder::DecodeGuard].map(&:name)
  end
end
