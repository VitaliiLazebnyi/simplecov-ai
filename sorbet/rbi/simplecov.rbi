# typed: strict

module SimpleCov
  # SimpleCov::Result#files returns a FileList (an Enumerable wrapper), not a plain Array.
  class FileList
    include Enumerable

    sig { params(arg: T.untyped, arg1: T.untyped, arg2: T.untyped).returns(T::Array[SimpleCov::SourceFile]) }
    def to_a(*arg, **arg1, &arg2); end

    sig do
      params(blk: T.proc.params(file: SimpleCov::SourceFile).returns(BasicObject))
        .returns(T::Array[SimpleCov::SourceFile])
    end
    def reject(&blk); end
  end

  class Result
    sig { returns(SimpleCov::FileList) }
    def files; end

    sig { params(arg: T.untyped, arg1: T.untyped, arg2: T.untyped).returns(Float) }
    def covered_percent(*arg, **arg1, &arg2); end

    # Aggregate branch counts are nil unless branch coverage is enabled.
    sig { params(arg: T.untyped, arg1: T.untyped, arg2: T.untyped).returns(T.nilable(Integer)) }
    def covered_branches(*arg, **arg1, &arg2); end

    sig { params(arg: T.untyped, arg1: T.untyped, arg2: T.untyped).returns(T.nilable(Integer)) }
    def total_branches(*arg, **arg1, &arg2); end
  end

  class SourceFile
    class Line
      sig { returns(Integer) }
      def line_number; end
    end

    class Branch
      sig { returns(Integer) }
      def start_line; end

      sig { returns(Integer) }
      def end_line; end

      sig { returns(Symbol) }
      def type; end
    end

    sig { returns(String) }
    def project_filename; end

    sig { returns(String) }
    def filename; end

    sig { params(criterion: T.untyped).returns(Float) }
    def covered_percent(criterion = nil); end

    sig { returns(T::Array[Line]) }
    def missed_lines; end

    sig { returns(T::Array[Branch]) }
    def missed_branches; end

    sig { returns(T::Array[Branch]) }
    def branches; end

    # Deprecated in simplecov >= 1.0 in favour of covered_percent(:branch); retained for
    # simplecov < 1.0 where covered_percent does not accept a coverage criterion.
    sig { returns(T.nilable(Float)) }
    def branches_coverage_percent; end

    sig { returns(T::Hash[BasicObject, BasicObject]) }
    def coverage_data; end
  end
end
