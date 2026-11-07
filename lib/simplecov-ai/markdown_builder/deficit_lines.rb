# typed: strong
# frozen_string_literal: true

module SimpleCov
  module Formatter
    class AIFormatter
      class MarkdownBuilder
        # Renders the deficit lines of one group: its never-invoked methods, then its missed
        # lines, then its missed branches.
        class DeficitLines
          extend T::Sig

          # Template for a method SimpleCov's method coverage reported as never invoked
          METHOD_DEFICIT_TMPL = '  - **Method Deficit:** [L%s] %s never invoked'
          # Template for a specific line deficit
          LINE_DEFICIT_TMPL = '  - **Line Deficit:** [L%d] %s %s'
          # Template for a specific branch deficit
          BRANCH_DEFICIT_TMPL = '  - **Branch Deficit:** [L%s] Missing coverage for %s branch: %s'

          # @param group [DeficitGroup] The group to render.
          # @param snippets [SnippetFormatter] The snippets of the group's file.
          # @param branch_columns [Hash] The branch column map from {BranchEnricher}.
          sig { params(group: DeficitGroup, snippets: SnippetFormatter, branch_columns: BranchEnricher::ColumnMap).void }
          def initialize(group, snippets, branch_columns)
            @group = group
            @node = T.let(group.semantic_node, T.nilable(ASTResolver::SemanticNode))
            @snippets = snippets
            @branch_columns = branch_columns
          end

          # @return [Array<String>] One Markdown line per deficit.
          sig { returns(T::Array[String]) }
          def render
            @group.method_deficits.map { |method_deficit| method_line(method_deficit) } +
              @group.lines.map { |line| line_line(line) } +
              @group.branches.map { |branch| branch_line(branch) }
          end

          private

          sig { params(method_deficit: MethodDeficit).returns(String) }
          def method_line(method_deficit)
            label = LineSpan.label(LineSpan.of(method_deficit))
            format(METHOD_DEFICIT_TMPL, label, InlineCode.span(display_name(method_deficit)))
          end

          # A method the resolver identified — a method node opening on the method's first line
          # and carrying its bare name — is named like its heading: `Owner.name` for a singleton
          # method, which SimpleCov's merged data reports under the plain owner name. A method the
          # resolver cannot see (a dynamic definition, an unparsable file, a same-named method
          # defined inside another) keeps the name SimpleCov derived, and so does one sharing its
          # first line with another definition (`def a; end; def b; end`): nodes carry no columns,
          # so the line's last node is not necessarily this method.
          sig { params(method_deficit: MethodDeficit).returns(String) }
          def display_name(method_deficit)
            if @node && @node.defines?(method_deficit.start_line, method_deficit.method_name)
              @node.name
            else
              method_deficit.name
            end
          end

          sig { params(line: SimpleCov::SourceFile::Line).returns(String) }
          def line_line(line)
            line_number = line.line_number
            snippet = InlineCode.span(@snippets.truncate(@snippets.text([line_number])))
            format(LINE_DEFICIT_TMPL, line_number, snippet, @snippets.occurrence(line_number, @node)).rstrip
          end

          # Each branch already carries a distinct sub-snippet (via column enrichment), so a
          # line-text occurrence count is not meaningful for branches — only for line deficits.
          sig { params(branch: SimpleCov::SourceFile::Branch).returns(String) }
          def branch_line(branch)
            range = LineSpan.of(branch)
            format(BRANCH_DEFICIT_TMPL, LineSpan.label(range), InlineCode.span(branch.type.to_s),
                   InlineCode.span(branch_snippet(branch, range)))
          end

          # An arm whose range strictly contains other missed arms of the group (the `else` of an
          # `elsif` chain spans the whole chain) would repeat every inner arm's text, so it is
          # cut to its first source line; every other arm quotes its exact expression. Strict
          # enclosure never holds between an arm and itself.
          sig { params(branch: SimpleCov::SourceFile::Branch, range: T::Range[Integer]).returns(String) }
          def branch_snippet(branch, range)
            if @group.branches.any? { |sibling| LineSpan.strictly_encloses?(range, LineSpan.of(sibling)) }
              @snippets.cut(range)
            else
              @snippets.truncate(@snippets.branch_text(branch, @branch_columns[branch]))
            end
          end
        end
      end
    end
  end
end
