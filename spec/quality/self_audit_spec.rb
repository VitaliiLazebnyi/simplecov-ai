# typed: false
# frozen_string_literal: true

require 'spec_helper'

# Audits the gem's own sources the way the formatter audits any project: every lib file is
# loaded as a SimpleCov::SourceFile and must come back with nothing skipped. SimpleCov honours
# a directive wherever it appears in a comment — to SimpleCov 1.x a doc comment that merely
# quotes `simplecov:disable` is an inline directive — which the directive auditor in
# directive_auditor_spec.rb cannot see, since it only matches lines that start with a marker.
# The probe coverage puts a covered branch and (SimpleCov >= 1.0) a covered method on every
# line, so a directive of any scope on any line surfaces as a skipped line, branch or method.
# (SimpleCov's own simulated coverage is not used: it recompiles the file through
# `Coverage.line_stub`, which resets the suite's live coverage of that file.)
module SelfAudit
  LIB_FILES = Dir.glob(File.expand_path('../../lib/**/*.rb', __dir__)).sort
end

RSpec.describe SelfAudit do
  def probe_coverage(path)
    line_numbers = (1..File.foreach(path).count)
    branches = line_numbers.to_h { |line| [[:if, line, line, 0, line, 0], { [:then, line, line, 0, line, 0] => 1 }] }
    methods = line_numbers.to_h { |line| [['Object', :"line_#{line}", line, 0, line, 0], 1] }
    { 'lines' => Array.new(line_numbers.count, 1), 'branches' => branches, 'methods' => methods }
  end

  def offenders
    described_class::LIB_FILES.flat_map do |path|
      file = source_file(path, probe_coverage(path))
      yield(file).map { |line_number| "#{file.project_filename}:#{line_number}" }
    end
  end

  it 'has no line SimpleCov skips in any lib file' do
    expect(offenders { |file| file.skipped_lines.map(&:line_number) }).to eq([])
  end

  it 'has no branch SimpleCov skips in any lib file' do
    expect(offenders { |file| file.branches.select(&:skipped?).map(&:start_line) }).to eq([])
  end

  it 'has no method SimpleCov skips in any lib file' do
    skip 'method coverage needs SimpleCov >= 1.0' unless method_coverage_supported?
    expect(offenders { |file| file.methods.select(&:skipped?).map(&:start_line) }).to eq([])
  end
end
