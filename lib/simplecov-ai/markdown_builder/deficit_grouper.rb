# typed: strict
# frozen_string_literal: true

module SimpleCov
  module Formatter
    class AIFormatter
      class MarkdownBuilder
        # Groups missed lines and branches into DeficitGroup objects based on AST semantic
        # boundaries. Every deficit inside the file lands on its innermost enclosing node (the
        # resolver's root scope at worst); only a deficit no node spans — reported by SimpleCov
        # for a file that vanished or shrank after coverage was recorded — falls back to a
        # positional label.
        class DeficitGrouper
          extend T::Sig

          # Positional label for a single-line deficit no resolved node spans; a missed line and
          # a single-line branch at the same line share it.
          FALLBACK_LINE_NAME = T.let('Line %d', String)
          # Positional label for a multi-line deficit no resolved node spans.
          FALLBACK_RANGE_NAME = T.let('Lines %d-%d', String)

          sig { returns(T::Hash[String, DeficitGroup]) }
          attr_reader :node_deficits

          sig { params(nodes: T::Array[ASTResolver::SemanticNode]).void }
          def initialize(nodes)
            @nodes = nodes
            @node_deficits = T.let({}, T::Hash[String, DeficitGroup])
            @sort_keys = T.let({}, T::Hash[String, [Integer, Integer, String]])
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

          # Orders groups by start line, then wider spans first so an enclosing node precedes the
          # children opening on its line, then name so two nodes sharing a span (a class and a
          # method defined on one line) always come out in the same order.
          sig { returns(T::Hash[String, DeficitGroup]) }
          def sort_deficits
            T.let(
              @node_deficits.sort_by { |group_key, _deficit_group| @sort_keys.fetch(group_key) }.to_h,
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
            group_for(matched_node, line_num, line_num).lines << line
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
            group_for(matched_node, start_line, end_line).branches << branch
          end

          # Finds or creates the group a deficit belongs to. Node-backed groups are keyed by name
          # plus start line so two same-named methods redefined in one file do not merge, and
          # the key's suffix never reaches the report; node-less groups are keyed by their
          # positional label, which doubles as the display name.
          sig do
            params(node: T.nilable(ASTResolver::SemanticNode), start_line: Integer, end_line: Integer)
              .returns(DeficitGroup)
          end
          def group_for(node, start_line, end_line)
            group_key, sort_key = node ? node_identity(node) : positional_identity(start_line, end_line)
            @sort_keys[group_key] ||= sort_key
            @node_deficits[group_key] ||= DeficitGroup.new(semantic_node: node)
          end

          sig { params(node: ASTResolver::SemanticNode).returns([String, [Integer, Integer, String]]) }
          def node_identity(node)
            ["#{node.name}@#{node.start_line}", [node.start_line, -node.end_line, node.name]]
          end

          sig { params(start_line: Integer, end_line: Integer).returns([String, [Integer, Integer, String]]) }
          def positional_identity(start_line, end_line)
            label = if start_line == end_line
                      format(FALLBACK_LINE_NAME, start_line)
                    else
                      format(FALLBACK_RANGE_NAME, start_line, end_line)
                    end
            [label, [start_line, -end_line, label]]
          end
        end
      end
    end
  end
end
