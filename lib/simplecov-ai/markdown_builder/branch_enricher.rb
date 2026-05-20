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
                  branch_hash.map do |branch_data, _hit_count|
                    T.cast(file.send(:restore_ruby_data_structure, branch_data), BasicObject)
                  end
                else
                  []
                end
              end
            end

            sig { params(branches: T::Array[SimpleCov::SourceFile::Branch], raw_branches: T::Array[BasicObject]).void }
            def apply_column_data(branches, raw_branches)
              branches.zip(raw_branches).each do |branch, raw|
                case raw
                when Array
                  next unless raw.size >= 6

                  branch.instance_variable_set(:@start_col, T.cast(raw[3], Integer))
                  branch.instance_variable_set(:@end_col, T.cast(raw[5], Integer))
                  branch.class.send(:attr_reader, :start_col, :end_col) unless branch.respond_to?(:start_col)
                end
              end
            end
          end
        end
      end
    end
  end
end
