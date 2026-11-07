# Copyright (c) 2026 Vitalii Lazebnyi
# typed: strong
# frozen_string_literal: true

require_relative '../ast_resolver/semantic_node'

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
          SINGLETON_OWNER_PATTERN = /\A#<Class:(.+)>\z/.freeze
          private_constant(:SINGLETON_OWNER_PATTERN)
          # Whether the installed SimpleCov implements method coverage at all (>= 1.0, where
          # SourceFile#missed_methods and Result#total_methods exist), decided once at load time.
          API_AVAILABLE = T.let(SimpleCov::SourceFile.method_defined?(:missed_methods), T::Boolean)
          public_constant(:API_AVAILABLE)

          # @return [String] The method's semantic name (`Klass#name` or `Klass.name`).
          const :name, String
          # @return [String] The bare method name, without its owner.
          const :method_name, String
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
            API_AVAILABLE && coverage_metrics.total_methods ? true : false
          end

          # The methods of a file SimpleCov reported as missed. SimpleCov reports methods only
          # with `enable_coverage :method` (>= 1.0); a file without method coverage has none.
          #
          # @param file [SimpleCov::SourceFile] The file to inspect.
          # @return [Array<MethodDeficit>] The missed methods in SimpleCov's order.
          sig { params(file: SimpleCov::SourceFile).returns(T::Array[MethodDeficit]) }
          def self.from_file(file)
            missed_methods = (API_AVAILABLE && file.missed_methods) || []
            missed_methods.map do |missed_method|
              method_name = missed_method.method_name.to_s
              new(
                name: qualified_name(missed_method.class_name.to_s, method_name),
                method_name: method_name,
                start_line: missed_method.start_line,
                end_line: missed_method.end_line
              )
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

          # The name the report gives this method under `node`, the node its deficit is grouped
          # under. A method the resolver identified - a method node opening on the method's first
          # line and carrying its bare name - is named like its heading: `Owner.name` for a
          # singleton method, which SimpleCov's merged data reports under the plain owner name. A
          # method the resolver cannot see (a dynamic definition, an unparsable file, a same-named
          # method defined inside another) keeps the name SimpleCov derived, and so does one
          # sharing its first line with another definition (`def a; end; def b; end`): nodes carry
          # no columns, so the line's last node is not necessarily this method.
          #
          # @param node [ASTResolver::SemanticNode, nil] The node of the deficit group.
          # @return [String] The node's name when it is this method's node, else {#name}.
          sig { params(node: T.nilable(ASTResolver::SemanticNode)).returns(String) }
          def display_name(node)
            own_name = name
            return own_name unless node

            node.defines?(start_line, method_name) ? node.name : own_name
          end
        end

        # Groups unexecuted lines, branches and methods under their common semantic node. The
        # props declare no `default:` - sorbet-runtime's default machinery
        # (`T::Props::Private::ApplyPrimitiveDefault`) fails on JRuby - so every construction
        # site passes the collections it starts from; the nilable node may be left out, and is
        # nil then.
        class DeficitGroup < T::Struct
          # @return [ASTResolver::SemanticNode, nil] The corresponding structural boundary
          prop :semantic_node, T.nilable(ASTResolver::SemanticNode)
          # @return [Array<SimpleCov::SourceFile::Line>] The missed source lines
          prop :lines, T::Array[SimpleCov::SourceFile::Line]
          # @return [Array<SimpleCov::SourceFile::Branch>] The missed conditional branches
          prop :branches, T::Array[SimpleCov::SourceFile::Branch]
          # @return [Array<MethodDeficit>] The methods never invoked
          prop :method_deficits, T::Array[MethodDeficit]
        end
      end
    end
  end
end
