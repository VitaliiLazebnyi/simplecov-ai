# typed: strict
# frozen_string_literal: true

module SimpleCov
  module Formatter
    class AIFormatter
      class MarkdownBuilder
        # Recovers the column offsets SimpleCov's Branch objects do not expose from the raw
        # coverage data, so a missed branch can quote its exact inline expression. Descriptors
        # are native Arrays in a live result and stringified (`"[:then, 1, 7, 18, 7, 22]"`) once
        # a result has been rebuilt from `.resultset.json` — SimpleCov's default, merged path —
        # and are decoded with SimpleCov's own parser (see {DECODER}). Data SimpleCov itself
        # cannot decode raises here exactly as it raises in SimpleCov, and the decode guard
        # contains that to the file.
        class BranchEnricher
          extend T::Sig

          # `[start_col, end_col]` byte offsets keyed by the SimpleCov branch they belong to
          # (by identity; SimpleCov's Branch objects are never modified).
          ColumnMap = T.type_alias { T::Hash[SimpleCov::SourceFile::Branch, [Integer, Integer]] }
          # Length of a [type, id, start_line, start_col, end_line, end_col] descriptor.
          DESCRIPTOR_LENGTH = T.let(6, Integer)
          # A descriptor decoder: takes the file and one raw descriptor, returns the decoded value.
          Decoder = T.type_alias { T.proc.params(file: SimpleCov::SourceFile, descriptor: BasicObject).returns(Object) }
          # Decodes with the eval-free `RubyDataParser` of SimpleCov >= 1.0.
          RUBY_DATA_PARSER_DECODER = T.let(
            ->(_file, descriptor) { SimpleCov::SourceFile::RubyDataParser.call(descriptor) },
            Decoder
          )
          # Decodes through the SourceFile's private `restore_ruby_data_structure` of SimpleCov < 1.0.
          LEGACY_DECODER = T.let(
            ->(file, descriptor) { T.cast(file.send(:restore_ruby_data_structure, descriptor), Object) },
            Decoder
          )
          # The decoder of the installed SimpleCov, chosen once at load time. Both return a
          # native Array as it is.
          DECODER = T.let(
            (defined?(SimpleCov::SourceFile::RubyDataParser) && RUBY_DATA_PARSER_DECODER) || LEGACY_DECODER, Decoder
          )

          # @param file [SimpleCov::SourceFile] The file whose branches need column data.
          # @return [Hash{SimpleCov::SourceFile::Branch => Array(Integer, Integer)}] The columns
          #   of every branch with a usable descriptor; empty when the raw data carries none.
          # @raise [StandardError, ScriptError] Whatever SimpleCov's decoder raises on a
          #   descriptor it cannot decode.
          sig { params(file: SimpleCov::SourceFile).returns(ColumnMap) }
          def self.enrich(file)
            columns_by_key = index_columns_by_key(raw_descriptors(file))
            file.branches.each_with_object(empty_column_map) do |branch, column_map|
              columns = columns_by_key[branch_key(branch.type, branch.start_line, branch.end_line)]&.shift
              column_map[branch] = columns if columns
            end
          end

          class << self
            extend T::Sig

            private

            sig { returns(ColumnMap) }
            def empty_column_map
              T.let({}.compare_by_identity, ColumnMap)
            end

            # The decoded descriptor of every arm. A `branches` entry or an arm map that is not
            # a Hash (foreign or absent data) carries no columns.
            sig { params(file: SimpleCov::SourceFile).returns(T::Array[Object]) }
            def raw_descriptors(file)
              conditions = Hash.try_convert(file.coverage_data['branches'])
              return [] unless conditions

              arm_maps = conditions.values.filter_map { |arms| Hash.try_convert(T.cast(arms, BasicObject)) }
              arm_maps.flat_map(&:keys).map { |descriptor| DECODER.call(file, T.cast(descriptor, BasicObject)) }
            end

            # Groups the raw column offsets by their (type, start_line, end_line) identity so
            # each SourceFile::Branch can be matched to its descriptor without relying on the
            # two collections sharing an identical iteration order.
            sig do
              params(raw_descriptors: T::Array[Object]).returns(T::Hash[String, T::Array[[Integer, Integer]]])
            end
            def index_columns_by_key(raw_descriptors)
              index = T.let({}, T::Hash[String, T::Array[[Integer, Integer]]])
              raw_descriptors.each do |raw|
                entry = column_entry(raw)
                next unless entry

                (index[entry.first] ||= []) << entry.last
              end
              index
            end

            # Converts a raw descriptor [type, id, start_line, start_col, end_line, end_col]
            # into a [key, [start_col, end_col]] pair, or nil if it is not a usable descriptor.
            sig { params(raw: Object).returns(T.nilable([String, [Integer, Integer]])) }
            def column_entry(raw)
              return nil unless raw.is_a?(Array) && raw.size >= DESCRIPTOR_LENGTH

              type, _id, start_line, start_col, end_line, end_col = raw
              key = branch_key(T.cast(type, Object), T.cast(start_line, Integer), T.cast(end_line, Integer))
              [key, [T.cast(start_col, Integer), T.cast(end_col, Integer)]]
            end

            sig { params(type: Object, start_line: Integer, end_line: Integer).returns(String) }
            def branch_key(type, start_line, end_line)
              "#{type}:#{start_line}:#{end_line}"
            end
          end
        end
      end
    end
  end
end
