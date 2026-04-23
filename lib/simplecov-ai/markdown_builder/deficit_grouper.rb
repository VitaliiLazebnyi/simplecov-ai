# typed: strict
# frozen_string_literal: true

module SimpleCov
  module Formatter
    class AIFormatter
      class MarkdownBuilder
        # Groups missed lines and branches into DeficitGroup objects based on AST semantic boundaries.
        class DeficitGrouper
          extend T::Sig

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
            grouper.node_deficits
          end

          sig { params(file: SimpleCov::SourceFile).void }
          def group_missed_lines(file)
            file.missed_lines.each do |line|
              line_num = line.line_number
              node = @nodes.find { |n| line_num.between?(n.start_line, n.end_line) }
              node_name = node ? node.name : "Line #{line_num}"
              @node_deficits[node_name] ||= DeficitGroup.new(semantic_node: node)
              T.must(@node_deficits[node_name]).lines << line
            end
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
            node = @nodes.find { |n| start_line >= n.start_line && end_line <= n.end_line }
            node_name = node ? node.name : "Lines #{start_line}-#{end_line}"
            @node_deficits[node_name] ||= DeficitGroup.new(semantic_node: node)
            T.must(@node_deficits[node_name]).branches << branch
          end
        end
      end
    end
  end
end
