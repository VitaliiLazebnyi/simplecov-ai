# typed: strict
# frozen_string_literal: true

require 'parser/current'

module SimpleCov
  module Formatter
    class AIFormatter
      # Employs statically-parsed Abstract Syntax Tree processing via the `parser` gem
      # to correlate raw line-based deficits with high-level semantically meaningful concepts
      # like Classes and Methods. This negates the line-number volatility often experienced
      # by Large Language Models when patching test coverage.
      class ASTResolver
        extend T::Sig

        # An immutable struct housing bounds, identification metrics, and static bypassing
        # definitions derived from traversing the AST nodes.
        class SemanticNode
          extend T::Sig

          sig { returns(String) }
          attr_reader :name, :type

          sig { returns(Integer) }
          attr_reader :start_line, :end_line

          sig { returns(T::Array[String]) }
          attr_reader :bypasses

          sig do
            params(
              name: String,
              type: String,
              start_line: Integer,
              end_line: Integer,
              bypasses: T::Array[String]
            ).void
          end
          def initialize(name:, type:, start_line:, end_line:, bypasses: [])
            @name = name
            @type = type
            @start_line = start_line
            @end_line = end_line
            @bypasses = bypasses
          end

          sig { params(bypass: String).void }
          def add_bypass(bypass)
            @bypasses << bypass
          end
        end

        # Orchestrates the initial mapping algorithm on a target file to extract structural
        # metadata, circumventing potential syntax violations explicitly.
        #
        # @param file_path [String] The absolute path to the Ruby script to parse.
        # @return [Array<SemanticNode>] A collection of resolvable structural entities.
        sig { params(file_path: String).returns(T::Array[SemanticNode]) }
        def self.resolve(file_path)
          return [] unless File.exist?(file_path)

          source = File.read(file_path)
          ast, comments = Parser::CurrentRuby.parse_with_comments(source)

          resolver = new
          nodes = resolver.traverse(ast)
          resolver.assign_bypasses(nodes, comments)
          nodes
        end

        # Recursively navigates an abstract node hierarchy, building SemanticNodes mappings
        # around modules, classes, singleton, and instance methods while aggregating parent paths.
        #
        # @param node [Parser::AST::Node] The root AST node from which traversal executes.
        # @param context [String] An accumulated identifier linking namespaces to inner entities.
        # @return [Array<SemanticNode>] Accumulation of all sub-tree defined endpoints.
        sig do
          params(node: T.nilable(Parser::AST::Node),
                 context: String).returns(T::Array[SemanticNode])
        end
        def traverse(node, context = '')
          return [] unless node.is_a?(Parser::AST::Node)

          nodes = T.let([], T::Array[SemanticNode])
          current_context, semantic_node = extract_node_metadata(node, context)
          nodes << semantic_node if semantic_node

          node.children.grep(Parser::AST::Node).each do |child|
            nodes.concat(traverse(child, current_context))
          end

          nodes
        end

        sig { params(nodes: T::Array[SemanticNode], comments: T::Array[Parser::Source::Comment]).void }
        def assign_bypasses(nodes, comments)
          comments.each do |c|
            c_text = T.cast(c.text, String)
            next unless c_text.include?(':nocov:')

            assign_bypass(nodes, c, c_text.strip)
          end
        end

        private

        sig { params(nodes: T::Array[SemanticNode], comment: Parser::Source::Comment, text: String).void }
        def assign_bypass(nodes, comment, text)
          c_loc = T.cast(comment.loc, Parser::Source::Map)
          c_line = T.cast(c_loc.line, Integer)

          innermost_node = nodes.reverse.find { |n| c_line.between?(n.start_line - 1, n.end_line + 1) }
          innermost_node&.add_bypass(text)
        end

        sig do
          params(node: Parser::AST::Node, context: String)
            .returns([String, T.nilable(SemanticNode)])
        end
        def extract_node_metadata(node, context)
          case node.type
          when :class, :module
            extract_class_metadata(node, context)
          when :def
            extract_instance_method_metadata(node, context)
          when :defs
            extract_singleton_method_metadata(node, context)
          else
            [context, nil]
          end
        end

        sig do
          params(node: Parser::AST::Node, context: String)
            .returns([String, T.nilable(SemanticNode)])
        end
        def extract_class_metadata(node, context)
          const_node = T.cast(node.children[0], Parser::AST::Node)
          const_node_name = T.cast(T.cast(const_node.loc, Parser::Source::Map::Constant).name, Parser::Source::Range)
          name = T.cast(const_node_name.source, String)
          ctx = context.empty? ? name : "#{context}::#{name}"
          [ctx, build_node(node, ctx, node.type.to_s.capitalize)]
        end

        sig do
          params(node: Parser::AST::Node, context: String)
            .returns([String, T.nilable(SemanticNode)])
        end
        def extract_instance_method_metadata(node, context)
          name = T.cast(node.children.first, Symbol).to_s
          ctx = context.empty? ? "##{name}" : "#{context}##{name}"
          [ctx, build_node(node, ctx, 'Instance Method')]
        end

        sig do
          params(node: Parser::AST::Node, context: String)
            .returns([String, T.nilable(SemanticNode)])
        end
        def extract_singleton_method_metadata(node, context)
          name = T.cast(node.children[1], Symbol).to_s
          ctx = context.empty? ? ".#{name}" : "#{context}.#{name}"
          [ctx, build_node(node, ctx, 'Singleton Method')]
        end

        sig do
          params(node: Parser::AST::Node, name: String,
                 type: String).returns(SemanticNode)
        end
        def build_node(node, name, type)
          loc = T.cast(node.loc, Parser::Source::Map)
          start_ln = T.cast(loc.line, Integer)
          end_ln = T.cast(loc.last_line, Integer)
          SemanticNode.new(name: name, type: type, start_line: start_ln, end_line: end_ln, bypasses: [])
        end
      end
    end
  end
end
