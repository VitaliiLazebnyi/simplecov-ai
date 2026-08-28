# typed: strict
# frozen_string_literal: true

module SimpleCov
  module Formatter
    class AIFormatter
      class ASTResolver
        # Scans raw source text for coverage-bypass regions and attributes them to the
        # semantic nodes they cover, mirroring SimpleCov's own semantics: `# :nocov:` markers
        # are paired into ranges (an unmatched marker extends to end-of-file), and
        # `# simplecov:disable` / `# simplecov:enable` block directives contribute their own
        # ranges. Each region is attributed to the outermost semantic nodes it fully contains,
        # or — when it sits inside a single node — to that innermost enclosing node.
        module BypassScanner
          extend T::Sig

          # Matches a standalone `# :nocov:` toggle line, mirroring SimpleCov's anchored
          # detection so trailing or prose mentions are ignored.
          NOCOV_LINE_PATTERN = T.let(/\A\s*#\s*#{Regexp.escape(Constants::NOCOV_DIRECTIVE)}/.freeze, Regexp)
          # Matches a standalone `# simplecov:disable` block directive (simplecov >= 1.0).
          DISABLE_LINE_PATTERN = T.let(/\A\s*#\s*simplecov\s*:\s*disable\b/.freeze, Regexp)
          # Matches a standalone `# simplecov:enable` block directive (simplecov >= 1.0).
          ENABLE_LINE_PATTERN = T.let(/\A\s*#\s*simplecov\s*:\s*enable\b/.freeze, Regexp)

          # Attributes every bypass region found in the source to the matching semantic nodes.
          #
          # @param nodes [Array<SemanticNode>] The resolved structural entities.
          # @param source [String] The full source text of the file.
          # @return [void]
          sig { params(nodes: T::Array[SemanticNode], source: String).void }
          def self.attribute(nodes, source)
            lines = source.lines
            (nocov_regions(lines) + directive_regions(lines)).each do |range, reason|
              attribute_region(nodes, range, reason)
            end
          end

          # Cheap pre-check (no AST parse) for whether a source could contain any bypass region,
          # so callers can skip the expensive full resolution of directive-free files.
          #
          # @param source [String] The full source text of a file.
          # @return [Boolean] Whether any nocov or simplecov:disable directive line is present.
          sig { params(source: String).returns(T::Boolean) }
          def self.contains_directive?(source)
            source.lines.any? { |line| NOCOV_LINE_PATTERN.match?(line) || DISABLE_LINE_PATTERN.match?(line) }
          end

          sig { params(lines: T::Array[String]).returns(T::Array[[T::Range[Integer], String]]) }
          def self.nocov_regions(lines)
            markers = collect_markers(lines)
            markers << [lines.size, ''] if markers.size.odd?

            markers.each_slice(2).map do |opening, closing|
              [(T.must(opening).first..T.must(closing).first), T.must(opening).last]
            end
          end

          sig { params(lines: T::Array[String]).returns(T::Array[[Integer, String]]) }
          def self.collect_markers(lines)
            markers = T.let([], T::Array[[Integer, String]])
            lines.each_with_index do |line, idx|
              markers << [idx + 1, line.strip] if NOCOV_LINE_PATTERN.match?(line)
            end
            markers
          end

          sig { params(lines: T::Array[String]).returns(T::Array[[T::Range[Integer], String]]) }
          def self.directive_regions(lines)
            regions = T.let([], T::Array[[T::Range[Integer], String]])
            open = T.let(nil, T.nilable([Integer, String]))
            lines.each_with_index { |line, idx| open = step_directive(regions, open, line, idx + 1) }
            regions << [(open.first..lines.size), open.last] if open
            regions
          end

          sig do
            params(regions: T::Array[[T::Range[Integer], String]], open: T.nilable([Integer, String]),
                   line: String, line_no: Integer).returns(T.nilable([Integer, String]))
          end
          def self.step_directive(regions, open, line, line_no)
            if DISABLE_LINE_PATTERN.match?(line)
              open || [line_no, line.strip]
            elsif ENABLE_LINE_PATTERN.match?(line) && open
              regions << [(open.first..line_no), open.last]
              nil
            else
              open
            end
          end

          sig { params(nodes: T::Array[SemanticNode], range: T::Range[Integer], reason: String).void }
          def self.attribute_region(nodes, range, reason)
            contained = nodes.select { |node| within_region?(node, range) }

            if contained.any?
              contained.reject { |node| contained.any? { |other| encloses?(other, node) } }
                       .each { |node| node.add_bypass(reason) }
            else
              innermost_enclosing(nodes, range)&.add_bypass(reason)
            end
          end

          sig { params(node: SemanticNode, range: T::Range[Integer]).returns(T::Boolean) }
          def self.within_region?(node, range)
            node.start_line >= range.begin && node.end_line <= range.end
          end

          # Nodes are in pre-order, so among the (nested) nodes enclosing a region the last one is
          # the innermost — including when an inner node spans exactly the same lines as its
          # parent (a method filling its class, or a class filling the root scope).
          sig { params(nodes: T::Array[SemanticNode], range: T::Range[Integer]).returns(T.nilable(SemanticNode)) }
          def self.innermost_enclosing(nodes, range)
            nodes.reverse.find { |node| node.start_line <= range.begin && node.end_line >= range.end }
          end

          sig { params(outer: SemanticNode, inner: SemanticNode).returns(T::Boolean) }
          def self.encloses?(outer, inner)
            outer.start_line <= inner.start_line && outer.end_line >= inner.end_line &&
              (outer.end_line - outer.start_line) > (inner.end_line - inner.start_line)
          end

          private_class_method :nocov_regions, :collect_markers, :directive_regions, :step_directive,
                               :attribute_region, :within_region?, :innermost_enclosing, :encloses?
        end
      end
    end
  end
end
