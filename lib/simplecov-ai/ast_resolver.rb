# typed: strict
# frozen_string_literal: true

require 'parser/current'
require_relative 'ast_resolver/semantic_node'
require_relative 'ast_resolver/bypass_scanner'
require_relative 'ast_resolver/metaclass_resolver'
require_relative 'ast_resolver/node_classifier'

module SimpleCov
  module Formatter
    class AIFormatter
      # Employs statically-parsed Abstract Syntax Tree processing via the `parser` gem
      # to correlate raw line-based deficits with high-level semantically meaningful concepts
      # like Classes and Methods. This negates the line-number volatility often experienced
      # by Large Language Models when patching test coverage.
      class ASTResolver
        extend T::Sig

        # Orchestrates the initial mapping algorithm on a target file to extract structural
        # metadata, circumventing potential syntax violations explicitly.
        #
        # @param file_path [String] The absolute path to the Ruby script to parse.
        # @return [Array<SemanticNode>] A collection of resolvable structural entities.
        sig { params(file_path: String).returns(T::Array[SemanticNode]) }
        def self.resolve(file_path)
          return [] unless File.exist?(file_path)

          source = File.read(file_path)
          ast, = Parser::CurrentRuby.parse_with_comments(source)

          resolver = new
          nodes = resolver.traverse(ast)
          resolver.assign_bypasses(nodes, source)
          nodes
        end

        # Recursively navigates an abstract node hierarchy, building SemanticNodes mappings
        # around modules, classes, singleton, and instance methods while aggregating parent paths.
        #
        # @param node [Parser::AST::Node] The root AST node from which traversal executes.
        # @param context [String] An accumulated identifier linking namespaces to inner entities.
        # @param singleton [Boolean] Whether the current lexical scope is a singleton class
        #   (`class << self`), in which case plain `def`s are singleton methods.
        # @return [Array<SemanticNode>] Accumulation of all sub-tree defined endpoints.
        sig do
          params(node: T.nilable(Parser::AST::Node), context: String, singleton: T::Boolean)
            .returns(T::Array[SemanticNode])
        end
        def traverse(node, context = '', singleton: false)
          return [] unless node.is_a?(Parser::AST::Node)

          nodes = T.let([], T::Array[SemanticNode])
          current_context, semantic_node, child_singleton = NodeClassifier.classify(node, context, singleton)
          nodes << semantic_node if semantic_node

          node.children.grep(Parser::AST::Node).each do |child|
            nodes.concat(traverse(child, current_context, singleton: child_singleton))
          end

          nodes
        end

        # Attributes coverage-bypass directives to the semantic nodes they cover.
        #
        # `# :nocov:` markers are paired into regions (mirroring SimpleCov's `each_slice(2)`
        # semantics, extending an unmatched marker to end-of-file), and `# simplecov:disable` /
        # `# simplecov:enable` block directives contribute their own regions. Each region is
        # attributed to the outermost semantic nodes it fully contains, or — when it sits inside
        # a single node — to that innermost enclosing node.
        #
        # @param nodes [Array<SemanticNode>] The resolved structural entities.
        # @param source [String] The full source text of the file.
        # @return [void]
        sig { params(nodes: T::Array[SemanticNode], source: String).void }
        def assign_bypasses(nodes, source)
          BypassScanner.attribute(nodes, source)
        end
      end
    end
  end
end
