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
        end

        # Orchestrates the initial mapping algorithm on a target file to extract structural
        # metadata, circumventing potential syntax violations explicitly.
        #
        # @param file_path [String] The absolute path to the Ruby script to parse.
        # @return [Array<SemanticNode>] A collection of resolvable structural entities.
        sig { params(file_path: String).returns(T::Array[SemanticNode]) }
        def self.resolve(file_path)
          return [] unless File.exist?(file_path)

          begin
            source = File.read(file_path)
            ast, comments = Parser::CurrentRuby.parse_with_comments(source)
            new.traverse(ast, comments)
          rescue Parser::SyntaxError
            []
          end
        end

        # Recursively navigates an abstract node hierarchy, building SemanticNodes mappings
        # around modules, classes, singleton, and instance methods while aggregating parent paths.
        #
        # @param node [Parser::AST::Node] The root AST node from which traversal executes.
        # @param comments [Array<Parser::Source::Comment>] Lexical comments corresponding to nodes.
        # @param context [String] An accumulated identifier linking namespaces to inner entities.
        # @return [Array<SemanticNode>] Accumulation of all sub-tree defined endpoints.
        sig do
          params(node: Parser::AST::Node, comments: T::Array[Parser::Source::Comment],
                 context: String).returns(T::Array[SemanticNode])
        end
        def traverse(node, comments, context = '')
          return [] unless node.is_a?(Parser::AST::Node)

          nodes = T.let([], T::Array[SemanticNode])
          current_context, semantic_node = extract_node_metadata(node, comments, context)
          nodes << semantic_node if semantic_node

          node.children.each do |child|
            case child
            when Parser::AST::Node
              nodes.concat(traverse(child, comments, current_context))
            end
          end

          nodes
        end

        private

        sig do
          params(node: Parser::AST::Node, comments: T::Array[Parser::Source::Comment], context: String)
            .returns([String, T.nilable(SemanticNode)])
        end
        def extract_node_metadata(node, comments, context)
          case node.type
          when :class, :module
            extract_class_metadata(node, comments, context)
          when :def
            extract_instance_method_metadata(node, comments, context)
          when :defs
            extract_singleton_method_metadata(node, comments, context)
          else
            [context, nil]
          end
        end

        sig do
          params(node: Parser::AST::Node, comments: T::Array[Parser::Source::Comment], context: String)
            .returns([String, T.nilable(SemanticNode)])
        end
        def extract_class_metadata(node, comments, context)
          const_node = T.cast(node.children[0], Parser::AST::Node)
          const_node_name = T.cast(T.cast(const_node.loc, Parser::Source::Map::Constant).name, Parser::Source::Range)
          name = T.cast(const_node_name.source, String)
          ctx = context.empty? ? name : "#{context}::#{name}"
          [ctx, build_node(node, comments, ctx, node.type.to_s.capitalize)]
        end

        sig do
          params(node: Parser::AST::Node, comments: T::Array[Parser::Source::Comment], context: String)
            .returns([String, T.nilable(SemanticNode)])
        end
        def extract_instance_method_metadata(node, comments, context)
          name = T.cast(node.children.first, Symbol).to_s
          ctx = context.empty? ? "##{name}" : "#{context}##{name}"
          [ctx, build_node(node, comments, ctx, 'Instance Method')]
        end

        sig do
          params(node: Parser::AST::Node, comments: T::Array[Parser::Source::Comment], context: String)
            .returns([String, T.nilable(SemanticNode)])
        end
        def extract_singleton_method_metadata(node, comments, context)
          name = T.cast(node.children[1], Symbol).to_s
          ctx = context.empty? ? ".#{name}" : "#{context}.#{name}"
          [ctx, build_node(node, comments, ctx, 'Singleton Method')]
        end

        sig do
          params(node: Parser::AST::Node, comments: T::Array[Parser::Source::Comment], name: String,
                 type: String).returns(SemanticNode)
        end
        def build_node(node, comments, name, type)
          loc = T.cast(node.loc, Parser::Source::Map)
          start_ln = T.cast(loc.line, Integer)
          end_ln = T.cast(loc.last_line, Integer)
          bypasses = extract_bypasses(comments, start_ln, end_ln)
          SemanticNode.new(name: name, type: type, start_line: start_ln, end_line: end_ln, bypasses: bypasses)
        end

        sig do
          params(comments: T::Array[Parser::Source::Comment], start_line: Integer, end_line: Integer)
            .returns(T::Array[String])
        end
        def extract_bypasses(comments, start_line, end_line)
          matched = comments.select do |c|
            c_loc = T.cast(c.loc, Parser::Source::Map)
            c_line = T.cast(c_loc.line, Integer)
            c_text = T.cast(c.text, String)
            c_line.between?(start_line - 1, end_line + 1) && c_text.include?(':nocov:')
          end
          matched.map { |c| T.cast(c.text, String).strip }
        end
      end
    end
  end
end
