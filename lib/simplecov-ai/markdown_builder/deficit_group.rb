# typed: strict
# frozen_string_literal: true

module SimpleCov
  module Formatter
    class AIFormatter
      class MarkdownBuilder
        # A method SimpleCov >= 1.0 reported as never invoked, captured in the formatter's own
        # shape so that no `SimpleCov::SourceFile::Method` constant (absent before 1.0) is ever
        # referenced at runtime.
        class MethodDeficit < T::Struct
          extend T::Sig

          # The class name Ruby reports for the owner of a singleton method.
          SINGLETON_OWNER_PATTERN = T.let(/\A#<Class:(.+)>\z/.freeze, Regexp)

          # @return [String] The method's semantic name (`Klass#name` or `Klass.name`).
          const :name, String
          # @return [Integer] The first line of the definition.
          const :start_line, Integer
          # @return [Integer] The last line of the definition.
          const :end_line, Integer

          # Whether SimpleCov measured method coverage in this run: SimpleCov >= 1.0 exposes
          # aggregate method counts on the result, which are nil unless `enable_coverage :method`
          # was on. Method deficits are only reported when this holds, mirroring the header (and
          # SimpleCov's own formatters), so stale `methods` entries never surface on their own.
          #
          # @param coverage_metrics [SimpleCov::Result] The result being formatted.
          # @return [Boolean] Whether method coverage was measured.
          sig { params(coverage_metrics: SimpleCov::Result).returns(T::Boolean) }
          def self.measured?(coverage_metrics)
            coverage_metrics.respond_to?(:total_methods) && !coverage_metrics.total_methods.nil?
          end

          # The methods of a file SimpleCov reported as missed. SimpleCov reports methods only
          # with `enable_coverage :method` (>= 1.0); a file without method coverage has none.
          #
          # @param file [SimpleCov::SourceFile] The file to inspect.
          # @return [Array<MethodDeficit>] The missed methods in SimpleCov's order.
          sig { params(file: SimpleCov::SourceFile).returns(T::Array[MethodDeficit]) }
          def self.from_file(file)
            missed_methods = (file.respond_to?(:missed_methods) && file.missed_methods) || []
            missed_methods.map do |missed_method|
              new(name: qualified_name(missed_method.class_name.to_s, missed_method.method_name.to_s),
                  start_line: missed_method.start_line, end_line: missed_method.end_line)
            end
          end

          # Names a method the way the AST resolver does: `Owner#name` for instance methods and
          # `Owner.name` when Ruby reports the owner as a singleton class (`#<Class:Owner>`).
          #
          # @param class_name [String] The owner as reported by Ruby's coverage data.
          # @param method_name [String] The bare method name.
          # @return [String] The qualified name.
          sig { params(class_name: String, method_name: String).returns(String) }
          def self.qualified_name(class_name, method_name)
            singleton_owner = class_name[SINGLETON_OWNER_PATTERN, 1]
            singleton_owner ? "#{singleton_owner}.#{method_name}" : "#{class_name}##{method_name}"
          end
        end

        # Groups unexecuted lines, branches and methods under their common semantic node.
        class DeficitGroup < T::Struct
          # @return [ASTResolver::SemanticNode, nil] The corresponding structural boundary
          prop :semantic_node, T.nilable(ASTResolver::SemanticNode), default: nil
          # @return [Array<SimpleCov::SourceFile::Line>] The missed source lines
          prop :lines, T::Array[SimpleCov::SourceFile::Line], default: []
          # @return [Array<SimpleCov::SourceFile::Branch>] The missed conditional branches
          prop :branches, T::Array[SimpleCov::SourceFile::Branch], default: []
          # @return [Array<MethodDeficit>] The methods never invoked
          prop :method_deficits, T::Array[MethodDeficit], default: []
        end
      end
    end
  end
end
