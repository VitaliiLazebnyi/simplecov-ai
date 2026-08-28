# typed: false
# frozen_string_literal: true

require 'spec_helper'
require 'bundler'

# Resolves the Ruby sources of every gem in the current bundle — thousands of files written by
# other people, parsed with the grammar of the running Ruby — and checks the resolver's
# structural contract on each of them: it raises nothing but Parser::SyntaxError, the root scope
# comes first and spans the whole file, every node has a non-empty name and a line range inside
# the file, and nodes come in source order. Files above MAX_FILE_BYTES (generated parser
# tables) are skipped for time, and the corpus is sampled at a fixed stride once it exceeds
# MAX_FILES (sized to keep the example around ten seconds on the slowest CI Ruby, where the
# `parser` gem does the parsing), so the selection is deterministic for a given bundle.
# RESOLVER_CORPUS_MAX_FILES=0 resolves every eligible file.
module ResolverCorpus
  MAX_FILE_BYTES = 200_000
  MAX_FILES = Integer(ENV.fetch('RESOLVER_CORPUS_MAX_FILES', 600))
  RESOLVER = SimpleCov::Formatter::AIFormatter::ASTResolver

  module_function

  # @return [Array<String>] The sampled corpus, sorted by path.
  def files
    eligible = eligible_files
    return eligible if MAX_FILES.zero? || eligible.size <= MAX_FILES

    eligible.each_slice((eligible.size.to_f / MAX_FILES).ceil).map(&:first)
  end

  def eligible_files
    gem_paths = Bundler.load.specs.map(&:full_gem_path).uniq.sort
    sources = gem_paths.flat_map { |gem_path| Dir.glob(File.join(gem_path, 'lib', '**', '*.rb')) }
    sources.uniq.sort.reject { |path| File.size(path) > MAX_FILE_BYTES }
  end

  # @return [Array<String>, :syntax_error] The contract violations of resolving `path`, or the
  #   marker for a file the running Ruby's grammar rejects (the one exception allowed).
  def violations(path)
    contract_violations(path, RESOLVER.resolve(path))
  rescue Parser::SyntaxError
    :syntax_error
  rescue StandardError, ScriptError => error
    ["#{path}: raised #{error.class}: #{error.message.lines.first}"]
  end

  def contract_violations(path, nodes)
    root, *rest = nodes
    return ["#{path}: resolved to no nodes"] unless root

    problems = root_violations(path, root)
    rest.each_with_index do |node, index|
      problems.concat(node_violations(node, index.zero? ? root : rest[index - 1], root))
    end
    problems.map { |problem| "#{path}: #{problem}" }
  end

  def root_violations(path, root)
    line_count = [RESOLVER.read_source(path).lines.size, 1].max
    problems = []
    problems << "first node is #{root.name} (#{root.type}), not the root scope" unless root.root?
    problems << "root spans #{root.line_range} for #{line_count} lines" unless root.line_range == (1..line_count)
    problems
  end

  def node_violations(node, previous, root)
    problems = identity_violations(node)
    problems << "#{node.name}: lines #{node.line_range}" unless inside?(node, root)
    problems << "#{node.name} follows #{previous.name}: #{order_of(node, previous)}" if out_of_order?(node, previous)
    problems
  end

  def identity_violations(node)
    problems = []
    problems << "#{node.name}: a second root scope" if node.root?
    problems << "empty name for #{node.type} at #{node.start_line}" if node.name.empty?
    problems
  end

  def inside?(node, root)
    node.start_line.between?(1, node.end_line) && node.end_line <= root.end_line
  end

  def out_of_order?(node, previous)
    node.start_line < previous.start_line
  end

  def order_of(node, previous)
    "line #{node.start_line} after line #{previous.start_line}"
  end
end

RSpec.describe ResolverCorpus do
  it 'resolves every sampled file of the bundle within the resolver contract' do
    files = described_class.files
    outcomes = files.map { |path| described_class.violations(path) }
    syntax_errors = outcomes.count(:syntax_error)
    violations = outcomes.grep(Array).flatten
    RSpec.configuration.reporter.message(
      "Resolver corpus: #{files.size} gem files resolved (#{syntax_errors} rejected by this Ruby's grammar)."
    )
    expect(violations).to be_empty, "Resolver contract violations:\n#{violations.first(20).join("\n")}"
  end
end
