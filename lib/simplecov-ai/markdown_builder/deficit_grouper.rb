# typed: strong
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
          FALLBACK_LINE_NAME = 'Line %d'
          # Positional label for a multi-line deficit no resolved node spans.
          FALLBACK_RANGE_NAME = 'Lines %d-%d'

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

          # @param node [ASTResolver::SemanticNode, nil] The innermost node covering the deficit.
          # @param range [Range<Integer>] The lines of the deficit.
          # @return [String] `Name@start_line` for a node; for a deficit no node spans `Line N` for
          #   one line, `Lines N-M` for a span.
          sig { params(node: T.nilable(ASTResolver::SemanticNode), range: T::Range[Integer]).returns(String) }
          def self.group_key(node, range)
            return "#{node.name}@#{node.start_line}" if node

            first = range.begin
            last = range.end
            first == last ? format(FALLBACK_LINE_NAME, first) : format(FALLBACK_RANGE_NAME, first, last)
          end

          sig { params(nodes: T::Array[ASTResolver::SemanticNode]).void }
          def initialize(nodes)
            @nodes = nodes
            @node_deficits = T.let({}, T::Hash[String, DeficitGroup])
            @sort_keys = T.let({}, T::Hash[String, [Integer, Integer]])
          end

          # Orders groups by start line, then wider spans first so an enclosing node precedes the
          # children opening on its line. No two groups share a span: every deficit inside a span
          # lands on the innermost node covering it.
          sig { returns(T::Hash[String, DeficitGroup]) }
          def sort_deficits
            @node_deficits.sort_by { |group_key, _group| @sort_keys.fetch(group_key) }.to_h
          end

          sig { params(file: SimpleCov::SourceFile).void }
          def group_missed_lines(file)
            file.missed_lines.each { |line| group_for(LineSpan.line(line.line_number)).lines << line }
          end

          sig { params(file: SimpleCov::SourceFile).void }
          def group_missed_branches(file)
            file.missed_branches.each { |branch| group_for(LineSpan.of(branch)).branches << branch }
          end

          sig { params(method_deficits: T::Array[MethodDeficit]).void }
          def group_missed_methods(method_deficits)
            method_deficits.each do |method_deficit|
              group_for(LineSpan.of(method_deficit)).method_deficits << method_deficit
            end
          end

          private

          # Finds or creates the group of the deficit spanning `range`: the group of the innermost
          # node covering it (nodes are in pre-order, so that is the last one), keyed by name
          # plus start line so two same-named methods redefined in one file do not merge — the
          # key's suffix never reaches the report. A range no node covers gets a node-less group
          # keyed by its positional label, which doubles as the display name.
          sig { params(range: T::Range[Integer]).returns(DeficitGroup) }
          def group_for(range)
            node = innermost_node(range)
            group_key = DeficitGrouper.group_key(node, range)
            @sort_keys[group_key] ||= LineSpan.sort_key(node ? node.line_range : range)
            @node_deficits[group_key] ||= DeficitGroup.new(semantic_node: node, lines: [], branches: [],
                                                           method_deficits: [])
          end

          # Nodes are in pre-order, so the last node covering a range is the innermost one.
          sig { params(range: T::Range[Integer]).returns(T.nilable(ASTResolver::SemanticNode)) }
          def innermost_node(range)
            @nodes.reverse.find { |node| LineSpan.encloses?(node.line_range, range) }
          end
        end
      end
    end
  end
end
