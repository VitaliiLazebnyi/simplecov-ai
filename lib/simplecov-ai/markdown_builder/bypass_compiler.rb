# typed: strict
# frozen_string_literal: true

module SimpleCov
  module Formatter
    class AIFormatter
      class MarkdownBuilder
        # Scans resolved AST blocks to report explicitly defined coverage ignores (e.g., :nocov:).
        class BypassCompiler
          extend T::Sig

          sig { params(result: SimpleCov::Result, builder: MarkdownBuilder).void }
          def initialize(result, builder)
            @result = result
            @builder = builder
          end

          sig { params(buffer: StringIO).void }
          def write_bypasses(buffer)
            bypass_buffer = T.let(StringIO.new, StringIO)
            has_bypasses = compile_all_bypasses(bypass_buffer)

            return unless has_bypasses

            buffer.puts "## Ignored Coverage Bypasses\n\n"
            buffer.puts bypass_buffer.string
          end

          private

          sig { params(buffer: StringIO).returns(T::Boolean) }
          def compile_all_bypasses(buffer)
            has_bypasses = false
            T.let(@result.files.to_a, T::Array[SimpleCov::SourceFile]).each do |file|
              bypassed = fetch_bypassed_nodes(file.filename)
              next if bypassed.empty?

              has_bypasses = true
              write_file_bypasses(buffer, file, bypassed)
            end
            has_bypasses
          end

          sig { params(filename: String).returns(T::Array[ASTResolver::SemanticNode]) }
          def fetch_bypassed_nodes(filename)
            nodes = @builder.try_resolve_ast(filename)
            nodes ? nodes.select { |n| n.bypasses.any? } : []
          end

          sig do
            params(buffer: StringIO, file: SimpleCov::SourceFile, bypasses: T::Array[ASTResolver::SemanticNode]).void
          end
          def write_file_bypasses(buffer, file, bypasses)
            buffer.puts "### `#{file.project_filename}`"
            bypasses.each do |node|
              buffer.puts "- `#{node.name}`\n  - **Bypass Present:** Contains `:nocov:` directive."
            end
            buffer.puts ''
          end
        end
      end
    end
  end
end
