# typed: false
# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'

# Property check over generated programs (see spec/support/program_generator.rb): for every
# program the resolver must derive exactly the node table the generator recorded while
# composing it — root scope first, then every class, module and method in pre-order with its
# expected `Ctx#name` / `Ctx.name` and line range — and the ranges must nest without partial
# overlap. Failures name the seed; RESOLVER_PROPERTY_SEED replays or shifts the sequence.
RSpec.describe SimpleCov::Formatter::AIFormatter::ASTResolver do
  let(:tmpdir) { Dir.mktmpdir('scai-property') }
  let(:base_seed) { Integer(ENV.fetch('RESOLVER_PROPERTY_SEED', ProgramGenerator::DEFAULT_SEED)) }

  after { FileUtils.remove_entry(tmpdir) }

  def resolve(source)
    path = File.join(tmpdir, 'generated.rb')
    File.write(path, source)
    described_class.resolve(path).map { |node| [node.name, node.type, node.start_line, node.end_line] }
  end

  # Every pair of nodes is either disjoint or nested, never partially overlapping.
  def overlaps(table)
    table.combination(2).select do |(_, _, outer_start, outer_end), (_, _, inner_start, inner_end)|
      inner_start <= outer_end && inner_start >= outer_start && inner_end > outer_end
    end
  end

  # @return [String, nil] A description of the failure for `seed`, or nil when the program resolves as expected.
  def failure_for(seed)
    source, expected_nodes = ProgramGenerator.new(seed).generate
    expected = expected_nodes.map(&:to_a)
    actual = resolve(source)
    return nil if actual == expected && overlaps(actual).empty?

    "seed #{seed}: expected #{expected}\n  actual #{actual}\n  overlaps #{overlaps(actual)}\n#{source}"
  rescue StandardError, ScriptError => error
    "seed #{seed}: raised #{error.class}: #{error.message}\n#{source}"
  end

  it "derives the exact node table of #{ProgramGenerator::PROGRAM_COUNT} generated programs" do
    failures = (0...ProgramGenerator::PROGRAM_COUNT).filter_map { |offset| failure_for(base_seed + offset) }
    expect(failures).to be_empty,
                        "#{failures.size} of #{ProgramGenerator::PROGRAM_COUNT} programs failed; first:\n#{failures.first}"
  end
end
