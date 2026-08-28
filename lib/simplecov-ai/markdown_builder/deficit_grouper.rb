# typed: strict
# frozen_string_literal: true

module SimpleCov
  module Formatter
    class AIFormatter
      class MarkdownBuilder
        # Groups missed lines, branches and methods into DeficitGroup objects based on AST
        # semantic boundaries. Every deficit inside the file lands on its innermost enclosing
        # node (the resolver's root scope at worst); only a deficit no node spans — reported by
        # SimpleCov for a file that vanished or shrank after coverage was recorded — falls back
        # to a positional label.
        class DeficitGrouper
          extend T::Sig

          # Positional label for a single-line deficit no resolved node spans; a missed line and
          # a single-line branch at the same line share it.
          FALLBACK_LINE_NAME = T.let('Line %d', String)
          # Positional label for a multi-line deficit no resolved node spans.
          FALLBACK_RANGE_NAME = T.let('Lines %d-%d', String)

          sig { params(nodes: T::Array[ASTResolver::SemanticNode]).void }
          def initialize(nodes)
            @nodes = nodes
            @node_deficits = T.let({}, T::Hash[String, DeficitGroup])
            @sort_keys = T.let({}, T::Hash[String, [Integer, Integer]])
          end

          # Groups every deficit of the file under its innermost node.
          #
          # @param file [SimpleCov::SourceFile] The file with deficits.
          # @param nodes [Array<ASTResolver::SemanticNode>] The file's resolved nodes.
          # @param method_deficits [Array<MethodDeficit>] The file's never-invoked methods.
          # @return [Hash{String => DeficitGroup}] Groups keyed by node identity, in source order.
          sig do
            params(file: SimpleCov::SourceFile, nodes: T::Array[ASTResolver::SemanticNode],
                   method_deficits: T::Array[MethodDeficit]).returns(T::Hash[String, DeficitGroup])
          end
          def self.build(file, nodes, method_deficits)
            grouper = new(nodes)
            grouper.group_missed_lines(file)
            grouper.group_missed_branches(file)
            grouper.group_missed_methods(method_deficits)
            grouper.sort_deficits
          end

          # The single node-less group used when a file's AST cannot be resolved: every deficit
          # SimpleCov reports, listed under its raw line numbers.
          #
          # @param file [SimpleCov::SourceFile] The file whose AST could not be resolved.
          # @param method_deficits [Array<MethodDeficit>] The file's never-invoked methods.
          # @return [DeficitGroup] All missed lines, branches and methods of the file.
          sig { params(file: SimpleCov::SourceFile, method_deficits: T::Array[MethodDeficit]).returns(DeficitGroup) }
          def self.raw_group(file, method_deficits)
            DeficitGroup.new(lines: file.missed_lines, branches: file.missed_branches, method_deficits: method_deficits)
          end

          # Orders groups by start line, then wider spans first so an enclosing node precedes the
          # children opening on its line. No two groups share a span: every deficit inside a span
          # lands on the innermost node covering it.
          sig { returns(T::Hash[String, DeficitGroup]) }
          def sort_deficits
            sorted = @node_deficits.sort_by { |group_key, _group| @sort_keys.fetch(group_key) }
            T.let(sorted.to_h, T::Hash[String, DeficitGroup])
          end

          sig { params(file: SimpleCov::SourceFile).void }
          def group_missed_lines(file)
            file.missed_lines.each do |line|
              line_number = line.line_number
              group_for(innermost_node_for(line_number, line_number), line_number, line_number).lines << line
            end
          end

          sig { params(file: SimpleCov::SourceFile).void }
          def group_missed_branches(file)
            file.missed_branches.each do |branch|
              matched_node = innermost_node_for(branch.start_line, branch.end_line)
              group_for(matched_node, branch.start_line, branch.end_line).branches << branch
            end
          end

          sig { params(method_deficits: T::Array[MethodDeficit]).void }
          def group_missed_methods(method_deficits)
            method_deficits.each do |method_deficit|
              start_line = method_deficit.start_line
              end_line = method_deficit.end_line
              deficit_group = group_for(innermost_node_for(start_line, end_line), start_line, end_line)
              deficit_group.method_deficits << method_deficit
            end
          end

          private

          # Nodes are in pre-order, so the last node spanning a range is the innermost one.
          sig { params(start_line: Integer, end_line: Integer).returns(T.nilable(ASTResolver::SemanticNode)) }
          def innermost_node_for(start_line, end_line)
            @nodes.reverse.find { |node| start_line >= node.start_line && end_line <= node.end_line }
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
            @node_deficits[group_key] ||=
              DeficitGroup.new(semantic_node: node, lines: [], branches: [], method_deficits: [])
          end

          sig { params(node: ASTResolver::SemanticNode).returns([String, [Integer, Integer]]) }
          def node_identity(node)
            ["#{node.name}@#{node.start_line}", [node.start_line, -node.end_line]]
          end

          sig { params(start_line: Integer, end_line: Integer).returns([String, [Integer, Integer]]) }
          def positional_identity(start_line, end_line)
            label = if start_line == end_line
                      format(FALLBACK_LINE_NAME, start_line)
                    else
                      format(FALLBACK_RANGE_NAME, start_line, end_line)
                    end
            [label, [start_line, -end_line]]
          end
        end
      end
    end
  end
end
