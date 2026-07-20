# typed: strict
# frozen_string_literal: true

module SimpleCov
  module Formatter
    class AIFormatter
      class MarkdownBuilder
        # Enriches SimpleCov branch data with column information from raw coverage data.
        class BranchEnricher
          extend T::Sig

          sig { params(file: SimpleCov::SourceFile).void }
          def self.enrich(file)
            return unless file.respond_to?(:coverage_data)

            case (cov = file.coverage_data)
            when Hash
              case (branches = cov['branches'])
              when Hash
                process_branches(file, branches)
              end
            end
          rescue StandardError
            nil
          end

          class << self
            extend T::Sig

            private

            sig { params(file: SimpleCov::SourceFile, branches: T::Hash[BasicObject, BasicObject]).void }
            def process_branches(file, branches)
              raw = extract_raw_branches(file, branches)
              apply_column_data(file.branches, raw)
            end

            sig { params(file: SimpleCov::SourceFile, branches: T::Hash[BasicObject, BasicObject]).returns(T::Array[BasicObject]) }
            def extract_raw_branches(file, branches)
              branches.flat_map do |_condition, branch_hash|
                case branch_hash
                when Hash
                  branch_hash.map { |data, _hits| decode_branch_data(file, T.cast(data, BasicObject)) }
                else
                  []
                end
              end
            end

            # Normalizes a raw branch descriptor into a plain Array of the form
            # [type, id, start_line, start_col, end_line, end_col].
            #
            # SimpleCov >= 1.0 already exposes these descriptors as native Arrays, whereas
            # older releases stringified them and provided the private
            # SourceFile#restore_ruby_data_structure helper to decode them. Both shapes are
            # handled so column enrichment works across the supported dependency range.
            sig { params(file: SimpleCov::SourceFile, branch_data: BasicObject).returns(BasicObject) }
            def decode_branch_data(file, branch_data)
              case branch_data
              when Array
                branch_data
              else
                return branch_data unless file.respond_to?(:restore_ruby_data_structure, true)

                T.cast(file.send(:restore_ruby_data_structure, branch_data), BasicObject)
              end
            end

            sig { params(branches: T::Array[SimpleCov::SourceFile::Branch], raw_branches: T::Array[BasicObject]).void }
            def apply_column_data(branches, raw_branches)
              columns_by_key = index_columns_by_key(raw_branches)

              branches.each do |branch|
                cols = columns_by_key[branch_key(branch.type, branch.start_line, branch.end_line)]&.shift
                next unless cols

                start_col, end_col = cols
                branch.instance_variable_set(:@start_col, start_col)
                branch.instance_variable_set(:@end_col, end_col)
              end
            end

            # Groups the raw column offsets by their (type, start_line, end_line) identity so
            # each SourceFile::Branch can be matched to its descriptor without relying on the
            # two collections sharing an identical iteration order.
            sig { params(raw_branches: T::Array[BasicObject]).returns(T::Hash[String, T::Array[[Integer, Integer]]]) }
            def index_columns_by_key(raw_branches)
              index = T.let({}, T::Hash[String, T::Array[[Integer, Integer]]])
              raw_branches.each do |raw|
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
                return nil unless raw.size >= 6

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
