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
          current_context = context

          case node.type
          when :class, :module
            name = node.children[0].loc.name.source
            current_context = context.empty? ? name : "#{context}::#{name}"
            nodes << build_node(node, comments, current_context, node.type.to_s.capitalize)
          when :def
            name = node.children.first.to_s
            current_context = context.empty? ? "##{name}" : "#{context}##{name}"
            nodes << build_node(node, comments, current_context, 'Instance Method')
          when :defs
            name = node.children[1].to_s
            current_context = context.empty? ? ".#{name}" : "#{context}.#{name}"
            nodes << build_node(node, comments, current_context, 'Singleton Method')
          end

          node.children.each do |child|
            nodes.concat(traverse(child, comments, current_context)) if child.is_a?(Parser::AST::Node)
          end

          nodes
        end

        private

        sig do
          params(node: Parser::AST::Node, comments: T::Array[Parser::Source::Comment], name: String,
                 type: String).returns(SemanticNode)
        end
        def build_node(node, comments, name, type)
          bypasses = comments.select do |c|
            c.loc.line >= node.loc.line - 1 && c.loc.line <= node.loc.last_line + 1 && c.text.include?(':nocov:')
          end.map { |c| c.text.strip }

          SemanticNode.new(
            name: name,
            type: type,
            start_line: node.loc.line,
            end_line: node.loc.last_line,
            bypasses: bypasses
          )
        end
      end
    end
  end
end
