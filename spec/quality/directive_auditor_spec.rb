# typed: false
# frozen_string_literal: true

require 'spec_helper'

module DirectiveAuditor; end

RSpec.describe DirectiveAuditor do
  extend T::Sig

  let(:forbidden_directives) do
    [
      /^\s*#\s*rubocop:disable/i,
      /^\s*#\s*:nocov:/i
    ]
  end

  sig { params(ruby_files: T::Array[String]).returns(T::Array[String]) }
  def collect_violations(ruby_files)
    ruby_files.each_with_object([]) do |file_path, violations|
      lines = File.readlines(file_path)
      lines.each_with_index do |line, index|
        check_line(file_path, line, index, lines, violations)
      end
    end
  end

  sig { params(file: String, line: String, index: Integer, lines: T::Array[String], violations: T::Array[String]).void }
  def check_line(file, line, index, lines, violations)
    return unless forbidden_directives.any? { |regex| line.match?(regex) }

    previous_line = index.positive? ? lines[index - 1].to_s.strip : ''
    return if previous_line.match?(/^#\s*(Justification|Reason):/i)

    violations << "#{file}:#{index + 1} contains unjustified bypass: #{line.strip}"
  end

  it 'ensures no bypass directives exist without explicit justification' do
    ruby_files = Dir.glob('{lib,spec}/**/*.rb')
    violations = collect_violations(ruby_files)
    expect(violations).to be_empty, "Found unjustified bypass directives:\n#{violations.join("\n")}"
  end
end
