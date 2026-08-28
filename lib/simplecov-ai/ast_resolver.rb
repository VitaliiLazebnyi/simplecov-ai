# typed: strict
# frozen_string_literal: true

require 'parser'
require_relative 'ast_resolver/semantic_node'
require_relative 'ast_resolver/parser_backend'
require_relative 'ast_resolver/bypass_scanner'
require_relative 'ast_resolver/metaclass_resolver'
require_relative 'ast_resolver/dynamic_method_resolver'
require_relative 'ast_resolver/receiver_resolver'
require_relative 'ast_resolver/node_classifier'

module SimpleCov
  module Formatter
    class AIFormatter
      # Employs statically-parsed Abstract Syntax Tree processing (Prism's `parser`-compatible
      # translation where available, the `parser` gem otherwise) to correlate raw line-based
      # deficits with high-level semantically meaningful concepts like Classes and Methods. This
      # negates the line-number volatility often experienced by Large Language Models when
      # patching test coverage.
      class ASTResolver
        extend T::Sig

        # Orchestrates the initial mapping algorithm on a target file to extract structural
        # metadata. The first node is always the synthetic root scope (`main`) spanning the
        # whole file, followed by the file's classes, modules and methods in source order.
        #
        # @param file_path [String] The absolute path to the Ruby script to parse.
        # @return [Array<SemanticNode>] The root scope followed by every resolvable structural
        #   entity in pre-order; empty when the file does not exist.
        # @raise [Parser::SyntaxError] When the file is not valid Ruby.
        sig { params(file_path: String).returns(T::Array[SemanticNode]) }
        def self.resolve(file_path)
          return [] unless File.exist?(file_path)

          buffer = Parser::Source::Buffer.new(file_path, source: read_source(file_path))
          ast = ParserBackend.parse(buffer)
          source = T.cast(buffer.source, String)

          resolver = new
          nodes = [SemanticNode.root(source.lines.size)] + resolver.traverse(ast)
          resolver.assign_bypasses(nodes, source)
          nodes
        end

        # Reads the file as bytes, tagged UTF-8 (Ruby's default source encoding) when they form
        # valid UTF-8 and left binary otherwise so the parser can still recover the structure
        # of a file with stray bytes. A `# encoding:` magic comment or byte-order mark is
        # honoured by the source buffer, which transcodes such files before parsing.
        #
        # @param file_path [String] The path of the file to read.
        # @return [String] The source bytes with their encoding tag.
        sig { params(file_path: String).returns(String) }
        def self.read_source(file_path)
          source = File.binread(file_path).force_encoding(Encoding::UTF_8)
          source.valid_encoding? ? source : source.force_encoding(Encoding::BINARY)
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
        # a single node — to that innermost enclosing node; a region wrapping only top-level
        # code therefore lands on the root scope.
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
