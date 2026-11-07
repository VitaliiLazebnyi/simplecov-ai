# Copyright (c) 2026 Vitalii Lazebnyi
# typed: strict
# frozen_string_literal: true

# Seeded generator of coverage hashes in the shapes a damaged `.resultset.json` can take:
# branch and method descriptors of the wrong length, type or content, hit counts that are not
# integers, line arrays with foreign values and entries that are not arrays or hashes at all.
# Everything is drawn from fixed alphabets so a generated string stays harmless on SimpleCov
# < 1.0, which decodes stringified descriptors with `eval`; descriptor keys become strings
# anyway when SimpleCov round-trips the hash through JSON.
class CoverageFuzzer
  extend T::Sig

  # How many resultsets the fuzz spec formats, and the first seed of its fixed sequence.
  CASE_COUNT = 150
  public_constant(:CASE_COUNT)
  DEFAULT_SEED = 20_260_501
  public_constant(:DEFAULT_SEED)
  DESCRIPTORS = T.let(
    [
      [:then, 1, 2, 4, 2, 9],
      [:else, 2, 2, 12, 2, 16],
      [:if, 0, 2, 2, 2, 16],
      ['Object', :plain, 1, 0, 3, 3],
      [:then, 1],
      [],
      [nil, nil, nil, nil, nil, nil],
      [:then, 'x', 2, 4, 2, 9],
      [:then, 1, 2, 4, 2, 9, 7, 8],
      [:then, 1, 99, 0, 98, 0],
      [:then, 1, -1, -1, -1, -1],
      [:then, 1, 2.5, 4, 2, 9],
      '[',
      '[:then, 1, 2',
      'nil',
      '42',
      'foo',
      '"str"',
      '',
      '[1, 2, 3, 4, 5, 6]',
      '[:then, 1, 2, 4, 2, 9]',
      'then',
      nil,
      42,
      3.5,
      true
      ].freeze,
    T::Array[Object]
  )
  private_constant(:DESCRIPTORS)
  HIT_COUNTS = T.let([0, 1, 7, -1, nil, 'x', [], {}, 2**70, 1.5].freeze, T::Array[Object])
  private_constant(:HIT_COUNTS)
  LINE_ARRAYS = T.let(
    [
      [1, 1, 0, nil],
      [0, 0, 0, 0],
      [nil, nil, nil, nil],
      ['x', 1, nil, nil],
      [1, 1, 0, nil, 1, 1, 1, 1, 1, 1],
      [],
      [1.5, 1, 0, nil],
      [-1, 1, 0, nil],
      [nil, 1, 0, nil]
      ].freeze,
    T::Array[T::Array[Object]]
  )
  private_constant(:LINE_ARRAYS)
  NOT_A_COLLECTION = T.let([nil, 42, 'x', true, []].freeze, T::Array[Object])
  private_constant(:NOT_A_COLLECTION)
  # The longest line array, which the fuzzed files are padded to.
  MAX_LINES = T.let(LINE_ARRAYS.map(&:size).max || 0, Integer)
  public_constant(:MAX_LINES)

  sig { params(seed: Integer).void }
  def initialize(seed)
    @random = T.let(Random.new(seed), Random)
  end

  # @return [Hash] A coverage hash for one file, in the shape SimpleCov::SourceFile takes.
  sig { returns(T::Hash[String, Object]) }
  def coverage
    coverage = T.let({ 'lines' => lines }, T::Hash[String, Object])
    coverage['branches'] = descriptor_map(nested: true) if @random.rand(4).positive?
    coverage['methods'] = descriptor_map(nested: false) if @random.rand(3).positive?
    coverage
  end

  private

  sig do
    type_parameters(:Candidate)
      .params(candidates: T::Array[T.type_parameter(:Candidate)])
      .returns(T.type_parameter(:Candidate))
  end
  def pick(candidates)
    candidates.fetch(@random.rand(candidates.size))
  end

  sig { returns(Object) }
  def lines
    @random.rand(6).zero? ? pick(NOT_A_COLLECTION) : pick(LINE_ARRAYS)
  end

  # Branches map a condition descriptor to a hash of arm descriptors and hit counts; methods
  # map a descriptor straight to its hit count. Occasionally the whole map is something else.
  sig { params(nested: T::Boolean).returns(Object) }
  def descriptor_map(nested:)
    return pick(NOT_A_COLLECTION) if @random.rand(6).zero?

    json_keyed(Array.new(@random.rand(4)) { [pick(DESCRIPTORS), nested ? arms : pick(HIT_COUNTS)] })
  end

  sig { returns(Object) }
  def arms
    return pick(NOT_A_COLLECTION) if @random.rand(6).zero?

    json_keyed(Array.new(@random.rand(4)) { [pick(DESCRIPTORS), pick(HIT_COUNTS)] })
  end

  # A resultset is JSON, whose object keys are the descriptors' string forms: a native descriptor
  # and its stringified twin would be one duplicated key there, which no real resultset holds
  # (and which the JSON parser warns about). The first of such twins is kept.
  sig { params(pairs: T::Array[[Object, Object]]).returns(T::Hash[Object, Object]) }
  def json_keyed(pairs)
    pairs.uniq { |descriptor, _value| descriptor.to_s }
      .to_h
  end
end
