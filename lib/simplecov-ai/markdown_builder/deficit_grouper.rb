# typed: strict
# frozen_string_literal: true

module SimpleCov
  module Formatter
    class AIFormatter
      class MarkdownBuilder
        # Groups missed lines and branches into DeficitGroup objects based on AST semantic boundaries.
        class DeficitGrouper
          extend T::Sig

          # Fallback identifier format for unassociated lines
          FALLBACK_LINE_NAME = T.let('Line %d', String)
          # Fallback identifier format for unassociated branches
          FALLBACK_BRANCH_NAME = T.let('Lines %d-%d', String)

          sig { returns(T::Hash[String, DeficitGroup]) }
          attr_reader :node_deficits

          sig { params(nodes: T::Array[ASTResolver::SemanticNode]).void }
          def initialize(nodes)
            @nodes = nodes
            @node_deficits = T.let({}, T::Hash[String, DeficitGroup])
          end

          sig do
            params(file: SimpleCov::SourceFile, nodes: T::Array[ASTResolver::SemanticNode])
              .returns(T::Hash[String, DeficitGroup])
          end
          def self.build(file, nodes)
            grouper = new(nodes)
            grouper.group_missed_lines(file)
            grouper.group_missed_branches(file)
            grouper.sort_deficits
          end

          sig { returns(T::Hash[String, DeficitGroup]) }
          def sort_deficits
            T.let(
              @node_deficits.sort_by do |node_name, deficit_group|
                semantic_node = deficit_group.semantic_node
                # Node-less groups are named "Line N" / "Lines N-M"; sort them by that number.
                semantic_node ? semantic_node.start_line : node_name[/\d+/].to_i
              end.to_h,
              T::Hash[String, DeficitGroup]
            )
          end

          sig { params(file: SimpleCov::SourceFile).void }
          def group_missed_lines(file)
            file.missed_lines.each do |line|
              add_missed_line(line)
            end
          end

          sig { params(line: SimpleCov::SourceFile::Line).void }
          def add_missed_line(line)
            line_num = line.line_number
            matched_node = @nodes.reverse.find { |node| line_num.between?(node.start_line, node.end_line) }
            key = group_key(matched_node, format(FALLBACK_LINE_NAME, line_num))
            (@node_deficits[key] ||= DeficitGroup.new(semantic_node: matched_node)).lines << line
          end

          # Builds a hash key that is unique per resolved node (name plus start line) so two
          # same-named methods redefined in one file do not merge into a single group; node-less
          # deficits fall back to their positional "Line N" / "Lines N-M" label.
          sig { params(node: T.nilable(ASTResolver::SemanticNode), fallback: String).returns(String) }
          def group_key(node, fallback)
            node ? "#{node.name}@#{node.start_line}" : fallback
          end

          sig { params(file: SimpleCov::SourceFile).void }
          def group_missed_branches(file)
            return unless file.respond_to?(:branches) && file.branches.any?

            file.missed_branches.each do |branch|
              add_missed_branch(branch)
            end
          end

          sig { params(branch: SimpleCov::SourceFile::Branch).void }
          def add_missed_branch(branch)
            start_line = branch.start_line
            end_line = branch.end_line
            matched_node = @nodes.reverse.find do |node|
              start_line >= node.start_line && end_line <= node.end_line
            end
            key = group_key(matched_node, format(FALLBACK_BRANCH_NAME, start_line, end_line))
            (@node_deficits[key] ||= DeficitGroup.new(semantic_node: matched_node)).branches << branch
          end
        end
      end
    end
  end
end
