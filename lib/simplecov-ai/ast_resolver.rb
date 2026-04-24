# typed: strict
# frozen_string_literal: true

require 'parser/current'
require_relative 'ast_resolver/semantic_node'

module SimpleCov
  module Formatter
    class AIFormatter
      # Employs statically-parsed Abstract Syntax Tree processing via the `parser` gem
      # to correlate raw line-based deficits with high-level semantically meaningful concepts
      # like Classes and Methods. This negates the line-number volatility often experienced
      # by Large Language Models when patching test coverage.
      class ASTResolver
        extend T::Sig

        NAMESPACE_SEPARATOR = T.let('::', String)
        INSTANCE_SEPARATOR = T.let('#', String)
        SINGLETON_SEPARATOR = T.let('.', String)
        TYPE_INSTANCE_METHOD = T.let('Instance Method', String)
        TYPE_SINGLETON_METHOD = T.let('Singleton Method', String)

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
          comments.each do |comment|
            comment_text = T.cast(comment.text, String)
            assign_bypass(nodes, comment, comment_text.strip) if comment_text.include?(Constants::NOCOV_DIRECTIVE)
          end
        end

        private

        sig { params(nodes: T::Array[SemanticNode], comment: Parser::Source::Comment, bypass_reason: String).void }
        def assign_bypass(nodes, comment, bypass_reason)
          comment_loc = T.cast(comment.loc, Parser::Source::Map)
          comment_line = T.cast(comment_loc.line, Integer)

          innermost_node = nodes.reverse.find { |node| comment_line.between?(node.start_line - 1, node.end_line + 1) }
          innermost_node&.add_bypass(bypass_reason)
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
          new_context = context.empty? ? name : "#{context}#{NAMESPACE_SEPARATOR}#{name}"
          [new_context, build_node(node, new_context, node.type.to_s.capitalize)]
        end

        sig do
          params(node: Parser::AST::Node, context: String)
            .returns([String, T.nilable(SemanticNode)])
        end
        def extract_instance_method_metadata(node, context)
          name = T.cast(node.children.first, Symbol).to_s
          new_context = context.empty? ? "#{INSTANCE_SEPARATOR}#{name}" : "#{context}#{INSTANCE_SEPARATOR}#{name}"
          [new_context, build_node(node, new_context, TYPE_INSTANCE_METHOD)]
        end

        sig do
          params(node: Parser::AST::Node, context: String)
            .returns([String, T.nilable(SemanticNode)])
        end
        def extract_singleton_method_metadata(node, context)
          name = T.cast(node.children[1], Symbol).to_s
          new_context = context.empty? ? "#{SINGLETON_SEPARATOR}#{name}" : "#{context}#{SINGLETON_SEPARATOR}#{name}"
          [new_context, build_node(node, new_context, TYPE_SINGLETON_METHOD)]
        end

        sig do
          params(node: Parser::AST::Node, name: String,
                 type: String).returns(SemanticNode)
        end
        def build_node(node, name, type)
          loc = T.cast(node.loc, Parser::Source::Map)
          start_line = T.cast(loc.line, Integer)
          end_line = T.cast(loc.last_line, Integer)
          SemanticNode.new(name: name, type: type, start_line: start_line, end_line: end_line, bypass_reasons: [])
        end
      end
    end
  end
end
