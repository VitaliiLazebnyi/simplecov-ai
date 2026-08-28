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
        # and the stringified form is decoded with SimpleCov's own parser: `RubyDataParser` on
        # >= 1.0, the private `restore_ruby_data_structure` before that.
        class BranchEnricher
          extend T::Sig

          # `[start_col, end_col]` byte offsets keyed by the SimpleCov branch they belong to
          # (by identity; SimpleCov's Branch objects are never modified).
          ColumnMap = T.type_alias { T::Hash[SimpleCov::SourceFile::Branch, [Integer, Integer]] }
          # Length of a [type, id, start_line, start_col, end_line, end_col] descriptor.
          DESCRIPTOR_LENGTH = T.let(6, Integer)

          # @param file [SimpleCov::SourceFile] The file whose branches need column data.
          # @return [Hash{SimpleCov::SourceFile::Branch => Array(Integer, Integer)}] The columns
          #   of every branch with a usable descriptor; empty when the raw data is unusable.
          sig { params(file: SimpleCov::SourceFile).returns(ColumnMap) }
          def self.enrich(file)
            columns_by_key = index_columns_by_key(raw_descriptors(file))
            file.branches.each_with_object(empty_column_map) do |branch, column_map|
              columns = columns_by_key[branch_key(branch.type, branch.start_line, branch.end_line)]&.shift
              column_map[branch] = columns if columns
            end
          rescue StandardError
            empty_column_map
          end

          class << self
            extend T::Sig

            private

            sig { returns(ColumnMap) }
            def empty_column_map
              T.let({}.compare_by_identity, ColumnMap)
            end

            sig { params(file: SimpleCov::SourceFile).returns(T::Array[BasicObject]) }
            def raw_descriptors(file)
              case (conditions = file.coverage_data['branches'])
              when Hash
                conditions.flat_map { |_condition, arms| decode_arms(file, T.cast(arms, BasicObject)) }
              else
                []
              end
            end

            sig { params(file: SimpleCov::SourceFile, arms: BasicObject).returns(T::Array[BasicObject]) }
            def decode_arms(file, arms)
              case arms
              when Hash
                arms.keys.map { |descriptor| decode_descriptor(file, T.cast(descriptor, BasicObject)) }
              else
                []
              end
            end

            sig { params(file: SimpleCov::SourceFile, descriptor: BasicObject).returns(BasicObject) }
            def decode_descriptor(file, descriptor)
              case descriptor
              when Array then descriptor
              else decode_stringified(file, descriptor)
              end
            end

            # SimpleCov >= 1.0 decodes stringified descriptors with the eval-free RubyDataParser
            # its own BranchBuilder uses; SimpleCov < 1.0 offers only the private
            # restore_ruby_data_structure. A descriptor neither can decode yields nil, and the
            # branch simply keeps its full-line snippet.
            sig { params(file: SimpleCov::SourceFile, descriptor: BasicObject).returns(BasicObject) }
            def decode_stringified(file, descriptor)
              parser_available = defined?(SimpleCov::SourceFile::RubyDataParser)
              return SimpleCov::SourceFile::RubyDataParser.call(descriptor) if parser_available
              return nil unless file.respond_to?(:restore_ruby_data_structure, true)

              T.cast(file.send(:restore_ruby_data_structure, descriptor), BasicObject)
            end

            # Groups the raw column offsets by their (type, start_line, end_line) identity so
            # each SourceFile::Branch can be matched to its descriptor without relying on the
            # two collections sharing an identical iteration order.
            sig do
              params(raw_descriptors: T::Array[BasicObject]).returns(T::Hash[String, T::Array[[Integer, Integer]]])
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
            sig { params(raw: BasicObject).returns(T.nilable([String, [Integer, Integer]])) }
            def column_entry(raw)
              case raw
              when Array
                return nil unless raw.size >= DESCRIPTOR_LENGTH

                key = branch_key(T.cast(raw[0], BasicObject), T.cast(raw[2], Integer), T.cast(raw[4], Integer))
                [key, [T.cast(raw[3], Integer), T.cast(raw[5], Integer)]]
              end
            end

            sig { params(type: BasicObject, start_line: Integer, end_line: Integer).returns(String) }
            def branch_key(type, start_line, end_line)
              "#{type}:#{start_line}:#{end_line}"
            end
          end
        end
      end
    end
  end
end
