# typed: strict

module SimpleCov
  class Result
    sig { returns(T::Array[SimpleCov::SourceFile]) }
    def files; end

    sig { params(arg: T.untyped, arg1: T.untyped, arg2: T.untyped).returns(Float) }
    def covered_percent(*arg, **arg1, &arg2); end

    sig { params(arg: T.untyped, arg1: T.untyped, arg2: T.untyped).returns(Integer) }
    def covered_branches(*arg, **arg1, &arg2); end

    sig { params(arg: T.untyped, arg1: T.untyped, arg2: T.untyped).returns(Integer) }
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
    end

    sig { returns(String) }
    def project_filename; end

    sig { returns(String) }
    def filename; end

    sig { returns(Float) }
    def covered_percent; end

    sig { returns(T::Array[Line]) }
    def missed_lines; end

    sig { returns(T::Array[Branch]) }
    def missed_branches; end

    sig { returns(T::Array[Branch]) }
    def branches; end
  end
end
