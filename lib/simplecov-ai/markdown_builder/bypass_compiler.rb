# typed: strict
# frozen_string_literal: true

module SimpleCov
  module Formatter
    class AIFormatter
      class MarkdownBuilder
        # Scans resolved AST blocks to report explicitly defined coverage ignores (e.g., :nocov:).
        class BypassCompiler
          extend T::Sig

          # Section heading for bypassed coverage
          HEADING = T.let("## Ignored Coverage Bypasses\n\n", String)
          # Template for formatting file headers in the bypass section
          FILE_HEADING_TEMPLATE = T.let('### `%s`', String)
          # Template for a bypassed node heading
          NODE_HEADING_TEMPLATE = T.let('- `%s`', String)
          # Template detailing the specific directive that ignored coverage for a node
          REASON_TEMPLATE = T.let('  - **Bypass Present:** Coverage explicitly ignored via `%s`.', String)

          sig { params(coverage_metrics: SimpleCov::Result, builder: MarkdownBuilder).void }
          def initialize(coverage_metrics, builder)
            @coverage_metrics = coverage_metrics
            @builder = builder
          end

          sig { params(buffer: StringIO).void }
          def write_bypasses(buffer)
            bypass_buffer = T.let(StringIO.new, StringIO)
            has_bypasses = compile_all_bypasses(bypass_buffer)

            return unless has_bypasses

            buffer.puts HEADING
            buffer.puts bypass_buffer.string
          end

          private

          sig { params(buffer: StringIO).returns(T::Boolean) }
          def compile_all_bypasses(buffer)
            has_bypasses = T.let(false, T::Boolean)
            T.let(@coverage_metrics.files.to_a, T::Array[SimpleCov::SourceFile]).each do |file|
              bypassed_nodes = fetch_bypassed_nodes(file.filename)
              next if bypassed_nodes.empty?

              has_bypasses = true
              write_file_bypasses(buffer, file, bypassed_nodes)
            end
            has_bypasses
          end

          sig { params(filename: String).returns(T::Array[ASTResolver::SemanticNode]) }
          def fetch_bypassed_nodes(filename)
            # Skip the expensive AST resolution for files that contain no bypass directive at all.
            return [] unless resolve_for_bypass?(filename)

            nodes = @builder.try_resolve_ast(filename)
            nodes ? nodes.select { |node| node.bypass_reasons.any? } : []
          end

          sig { params(filename: String).returns(T::Boolean) }
          def resolve_for_bypass?(filename)
            ASTResolver::BypassScanner.contains_directive?(File.read(filename))
          rescue StandardError
            # If the file cannot be cheaply scanned, fall through to full resolution rather than
            # silently dropping a possible bypass; resolution is itself cheap for unreadable files.
            true
          end

          sig do
            params(buffer: StringIO, file: SimpleCov::SourceFile, bypassed_nodes: T::Array[ASTResolver::SemanticNode]).void
          end
          def write_file_bypasses(buffer, file, bypassed_nodes)
            buffer.puts format(FILE_HEADING_TEMPLATE, file.project_filename.delete_prefix('/'))
            bypassed_nodes.each do |node|
              buffer.puts format(NODE_HEADING_TEMPLATE, node.name)
              node.bypass_reasons.each { |reason| buffer.puts format(REASON_TEMPLATE, reason) }
            end
            buffer.puts ''
          end
        end
      end
    end
  end
end
