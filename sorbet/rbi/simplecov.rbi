# typed: strict

# Typed overlay for the `simplecov` gem. The generated RBI under sorbet/rbi/gems reflects every
# method but carries no signatures, and `srb tc --typed strong` rejects untyped intermediate
# values, so the SimpleCov API the library consumes directly is given signatures here. Each
# definition must keep the exact arity of its generated counterpart (delegated methods are
# `(*args, **kwargs, &block)`), otherwise Sorbet reports a conflicting redefinition. Methods the
# library narrows with `T.cast` at the call site (e.g. `SimpleCov.root`) are deliberately left
# untyped so those casts stay meaningful. Members that only exist on simplecov >= 1.0 are noted;
# the library reaches them behind `respond_to?` / `defined?` guards and never names them in a
# runtime-evaluated signature, so it still loads on simplecov < 1.0.
module SimpleCov
  # SimpleCov extends Configuration, so these are the `SimpleCov.<setting>` readers.
  module Configuration
    # SimpleCov's output directory (`root` joined with `coverage_dir`), created on demand.
    sig { params(path: T.nilable(String)).returns(String) }
    def coverage_path(path = nil); end
  end

  # SimpleCov::Result#files returns a FileList (an Enumerable wrapper), not a plain Array.
  class FileList
    sig { params(arg: T.untyped, arg1: T.untyped, arg2: T.untyped).returns(T::Array[SimpleCov::SourceFile]) }
    def to_a(*arg, **arg1, &arg2); end

    sig { params(arg: T.untyped, arg1: T.untyped, arg2: T.untyped).returns(Integer) }
    def size(*arg, **arg1, &arg2); end

    sig do
      params(blk: T.proc.params(file: SimpleCov::SourceFile).returns(BasicObject))
        .returns(T::Array[SimpleCov::SourceFile])
    end
    def reject(&blk); end
  end

  class Result
    sig { returns(SimpleCov::FileList) }
    def files; end

    # Nil on simplecov >= 1.0 when line coverage was disabled for the run (a branch- or
    # method-only run).
    sig { params(arg: T.untyped, arg1: T.untyped, arg2: T.untyped).returns(T.nilable(Float)) }
    def covered_percent(*arg, **arg1, &arg2); end

    # Aggregate branch counts are nil unless branch coverage is enabled.
    sig { params(arg: T.untyped, arg1: T.untyped, arg2: T.untyped).returns(T.nilable(Integer)) }
    def covered_branches(*arg, **arg1, &arg2); end

    sig { params(arg: T.untyped, arg1: T.untyped, arg2: T.untyped).returns(T.nilable(Integer)) }
    def total_branches(*arg, **arg1, &arg2); end

    # simplecov >= 1.0 only; aggregate method counts are nil unless method coverage is enabled.
    sig { params(arg: T.untyped, arg1: T.untyped, arg2: T.untyped).returns(T.nilable(Integer)) }
    def covered_methods(*arg, **arg1, &arg2); end

    sig { params(arg: T.untyped, arg1: T.untyped, arg2: T.untyped).returns(T.nilable(Integer)) }
    def total_methods(*arg, **arg1, &arg2); end
  end

  class SourceFile
    class Line
      sig { returns(Integer) }
      def line_number; end

      sig { returns(T::Boolean) }
      def skipped?; end
    end

    class Branch
      sig { returns(Integer) }
      def start_line; end

      sig { returns(Integer) }
      def end_line; end

      sig { returns(Symbol) }
      def type; end

      sig { returns(T::Boolean) }
      def skipped?; end
    end

    # simplecov >= 1.0 only: a method reported by `enable_coverage :method`.
    class Method
      # The owner is a Module in a live result and a String once rebuilt from .resultset.json.
      sig { returns(T.any(String, T::Module[T.anything])) }
      def class_name; end

      sig { returns(T.any(String, Symbol)) }
      def method_name; end

      sig { returns(Integer) }
      def start_line; end

      sig { returns(Integer) }
      def end_line; end
    end

    # simplecov >= 1.0 only: decodes a stringified branch or method descriptor without eval.
    module RubyDataParser
      sig { params(structure: BasicObject).returns(T::Array[BasicObject]) }
      def self.call(structure); end
    end

    sig { returns(String) }
    def project_filename; end

    sig { returns(String) }
    def filename; end

    # simplecov >= 1.0 accepts a coverage criterion (:line / :branch / :method); older releases
    # take no argument and raise ArgumentError when one is passed, which the library rescues.
    sig { params(criterion: T.untyped).returns(Float) }
    def covered_percent(criterion = nil); end

    # The source lines SimpleCov loaded (transcoded to UTF-8, trailing newlines kept).
    sig { returns(T::Array[String]) }
    def src; end

    sig { returns(T::Array[Line]) }
    def missed_lines; end

    sig { returns(T::Array[Line]) }
    def skipped_lines; end

    sig { returns(T::Array[Branch]) }
    def missed_branches; end

    sig { returns(T::Array[Branch]) }
    def branches; end

    # simplecov >= 1.0 only; empty unless `enable_coverage :method`.
    sig { returns(T::Array[Method]) }
    def missed_methods; end

    # Deprecated in simplecov >= 1.0 in favour of covered_percent(:branch); retained for
    # simplecov < 1.0 where covered_percent does not accept a coverage criterion.
    sig { returns(T.nilable(Float)) }
    def branches_coverage_percent; end

    sig { returns(T::Hash[BasicObject, BasicObject]) }
    def coverage_data; end
  end
end
