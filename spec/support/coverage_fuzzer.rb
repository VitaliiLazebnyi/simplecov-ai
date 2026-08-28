# typed: false
# frozen_string_literal: true

# Seeded generator of coverage hashes in the shapes a damaged `.resultset.json` can take:
# branch and method descriptors of the wrong length, type or content, hit counts that are not
# integers, line arrays with foreign values and entries that are not arrays or hashes at all.
# Everything is drawn from fixed alphabets so a generated string stays harmless on SimpleCov
# < 1.0, which decodes stringified descriptors with `eval`; descriptor keys become strings
# anyway when SimpleCov round-trips the hash through JSON.
class CoverageFuzzer
  # How many resultsets the fuzz spec formats, and the first seed of its fixed sequence.
  CASE_COUNT = 150
  DEFAULT_SEED = 20_260_501
  DESCRIPTORS = [
    [:then, 1, 2, 4, 2, 9], [:else, 2, 2, 12, 2, 16], [:if, 0, 2, 2, 2, 16], ['Object', :plain, 1, 0, 3, 3],
    [:then, 1], [], [nil, nil, nil, nil, nil, nil], [:then, 'x', 2, 4, 2, 9], [:then, 1, 2, 4, 2, 9, 7, 8],
    [:then, 1, 99, 0, 98, 0], [:then, 1, -1, -1, -1, -1], [:then, 1, 2.5, 4, 2, 9],
    '[', '[:then, 1, 2', 'nil', '42', 'foo', '"str"', '', '[1, 2, 3, 4, 5, 6]', '[:then, 1, 2, 4, 2, 9]', 'then',
    nil, 42, 3.5, true
  ].freeze
  HIT_COUNTS = [0, 1, 7, -1, nil, 'x', [], {}, 2**70, 1.5].freeze
  LINE_ARRAYS = [
    [1, 1, 0, nil], [0, 0, 0, 0], [nil, nil, nil, nil], ['x', 1, nil, nil], [1, 1, 0, nil, 1, 1, 1, 1, 1, 1], [],
    [1.5, 1, 0, nil], [-1, 1, 0, nil], [nil, 1, 0, nil]
  ].freeze
  NOT_A_COLLECTION = [nil, 42, 'x', true, []].freeze

  def initialize(seed)
    @random = Random.new(seed)
  end

  # @return [Hash] A coverage hash for one file, in the shape SimpleCov::SourceFile takes.
  def coverage
    coverage = { 'lines' => lines }
    coverage['branches'] = descriptor_map(nested: true) if @random.rand(4).positive?
    coverage['methods'] = descriptor_map(nested: false) if @random.rand(3).positive?
    coverage
  end

  private

  def pick(candidates)
    candidates.fetch(@random.rand(candidates.size))
  end

  def lines
    @random.rand(6).zero? ? pick(NOT_A_COLLECTION) : pick(LINE_ARRAYS)
  end

  # Branches map a condition descriptor to a hash of arm descriptors and hit counts; methods
  # map a descriptor straight to its hit count. Occasionally the whole map is something else.
  def descriptor_map(nested:)
    return pick(NOT_A_COLLECTION) if @random.rand(6).zero?

    @random.rand(4).times.to_h do
      [pick(DESCRIPTORS), nested ? arms : pick(HIT_COUNTS)]
    end
  end

  def arms
    return pick(NOT_A_COLLECTION) if @random.rand(6).zero?

    @random.rand(4).times.to_h { [pick(DESCRIPTORS), pick(HIT_COUNTS)] }
  end
end
