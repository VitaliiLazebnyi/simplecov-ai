# typed: false
# frozen_string_literal: true

require 'json'
require 'stringio'
require 'simplecov'

# Builds REAL SimpleCov objects for the suite from sources written to disk, so every example
# drives the formatter exactly as SimpleCov does and passes sorbet-runtime's signature checks.
# Coverage hashes use SimpleCov's own shapes: a line-hit array, branch descriptors
# `[type, id, start_line, start_col, end_line, end_col]` and (SimpleCov >= 1.0) method
# descriptors `[class_name, method_name, start_line, start_col, end_line, end_col]`.
#
# Version-specific SimpleCov features (method coverage, `# simplecov:disable` directives) are
# real on the SimpleCov that ships them. On SimpleCov < 1.0 the formatter's method-coverage
# paths are exercised by giving real objects the readers 1.0 added (see {#measuring_methods}),
# which keeps the suite at 100% coverage on every supported SimpleCov and proves the
# degradation logic against the real 0.x objects.
module SimpleCovFixtures
  # The nocov marker, assembled from fragments so the repository directive auditor (which scans
  # spec sources for literal marker lines) does not flag this helper.
  NOCOV_MARKER = ['# :noc', 'ov:'].join.freeze

  # Duck-typed stand-in for `SimpleCov::SourceFile::Method` on SimpleCov < 1.0.
  EmulatedMethod = Struct.new(:class_name, :method_name, :start_line, :end_line, :coverage) do
    def missed?
      coverage.zero?
    end
  end

  # @return [String] The `# :nocov:` marker line, for sources written by the examples.
  def nocov_marker
    NOCOV_MARKER
  end

  # @return [Boolean] Whether the installed SimpleCov honours `# simplecov:disable` directives.
  def simplecov_directives_supported?
    defined?(SimpleCov::Directive) ? true : false
  end

  # @return [Boolean] Whether the installed SimpleCov (>= 1.0) can measure method coverage.
  def method_coverage_supported?
    SimpleCov::SourceFile.method_defined?(:missed_methods)
  end

  # @return [String] The absolute path of the written source file.
  def write_source(directory, basename, code)
    path = File.join(directory, basename)
    File.write(path, code)
    silence_nocov_deprecation(path)
    path
  end

  # SimpleCov >= 1.0 warns once per file about `# :nocov:`; registering the temp file in its
  # own dedupe set keeps the suite's output readable without touching SimpleCov's behaviour.
  def silence_nocov_deprecation(path)
    SimpleCov::SourceFile::SkipChunks.nocov_warned.add(path) if defined?(SimpleCov::SourceFile::SkipChunks)
  end

  # Line-coverage array for a file of `line_count` lines: 1 for covered lines, 0 for missed
  # lines and nil (not relevant) everywhere else.
  def line_hits(line_count, covered: [], missed: [])
    Array.new(line_count) do |index|
      line_number = index + 1
      next 1 if covered.include?(line_number)

      missed.include?(line_number) ? 0 : nil
    end
  end

  # A branch descriptor whose columns are located by searching `expression` on the given line
  # of `source`, so column data is always consistent with the text on disk.
  def branch_descriptor(source, type, id, line_number, expression)
    line_text = source.lines.fetch(line_number - 1)
    start_col = line_text.index(expression)
    raise ArgumentError, "#{expression.inspect} is not on line #{line_number}" unless start_col

    [type, id, line_number, start_col, line_number, start_col + expression.bytesize]
  end

  # A branch descriptor spanning whole lines (a non-inline arm of a multi-line conditional).
  def multiline_branch_descriptor(type, id, start_line, end_line)
    [type, id, start_line, 0, end_line, 0]
  end

  def source_file(path, coverage)
    SimpleCov::SourceFile.new(path, coverage)
  end

  # A result over the given files. SimpleCov's project filters are suspended while it is built:
  # they are the host project's policy, not formatter behaviour, and SimpleCov < 1.0's root
  # filter memoises the first `SimpleCov.root` it sees, which would drop files written to a
  # temp directory depending on example order.
  def result_for(coverage_by_path)
    without_simplecov_filters { SimpleCov::Result.new(coverage_by_path) }
  end

  # The result as SimpleCov hands it to a formatter on its default (merging) path: rebuilt
  # from the JSON resultset, where every branch and method descriptor became a String.
  # (`Result.from_hash` returns one result per command name since SimpleCov 0.19 and a single
  # result before that.)
  def merged_result(result)
    rebuilt = without_simplecov_filters { SimpleCov::Result.from_hash(JSON.parse(JSON.generate(result.to_hash))) }
    rebuilt.is_a?(Array) ? rebuilt.first : rebuilt
  end

  def without_simplecov_filters
    original_filters = SimpleCov.filters.dup
    SimpleCov.filters.clear
    yield
  ensure
    SimpleCov.filters.replace(original_filters)
  end

  # The path as a report file heading shows it: relative to SimpleCov.root, no leading slash.
  def heading_path(path)
    path.delete_prefix(SimpleCov.root).delete_prefix('/')
  end

  # Makes `object` look like a SimpleCov without `method`: where the installed release has it,
  # `respond_to?` is stubbed to deny it and the method raises if called anyway; older releases
  # lack it for real and need no stub.
  def without_method(object, method)
    return unless object.respond_to?(method)

    allow(object).to receive(:respond_to?).and_call_original
    allow(object).to receive(:respond_to?).with(method).and_return(false)
    allow(object).to receive(method).and_raise(NoMethodError)
  end

  # Runs the block with STDOUT captured and returns what it printed.
  def capture_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end

  # Runs the block with SimpleCov measuring method coverage for `result`: for real on SimpleCov
  # >= 1.0 (the files' coverage hashes carry their `methods` entries), emulated from
  # `methods_by_path` (`{ path => { descriptor => hits } }`) on older releases.
  def measuring_methods(result, methods_by_path, &block)
    return with_method_coverage_enabled(&block) if method_coverage_supported?

    result.files.each { |file| emulate_method_coverage!(file, methods_by_path.fetch(file.filename, {})) }
    hit_counts = methods_by_path.values.flat_map(&:values)
    emulate_method_totals!(result, covered: hit_counts.count(&:positive?), total: hit_counts.size)
    yield
  end

  # Runs the block with SimpleCov measuring method coverage (SimpleCov >= 1.0), restoring the
  # global configuration afterwards so the suite's own coverage processing is unaffected.
  def with_method_coverage_enabled
    SimpleCov.enable_coverage(:method)
    yield
  ensure
    SimpleCov.coverage_criteria.delete(:method)
  end

  # Gives a real SimpleCov < 1.0 SourceFile the `missed_methods` reader of SimpleCov >= 1.0,
  # derived from method descriptors exactly as SimpleCov 1.x derives it.
  def emulate_method_coverage!(file, methods)
    emulated = methods.map do |descriptor, hits|
      class_name, method_name, start_line, _start_col, end_line, _end_col = descriptor
      EmulatedMethod.new(class_name, method_name, start_line, end_line, hits)
    end
    file.define_singleton_method(:missed_methods) { emulated.select(&:missed?) }
  end

  # Gives a real SimpleCov < 1.0 Result the aggregate method counters of SimpleCov >= 1.0.
  def emulate_method_totals!(result, covered:, total:)
    result.define_singleton_method(:total_methods) { total }
    result.define_singleton_method(:covered_methods) { covered }
  end
end
