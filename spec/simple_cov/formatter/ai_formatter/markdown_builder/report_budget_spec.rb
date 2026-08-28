# typed: false
# frozen_string_literal: true

require 'spec_helper'
require 'stringio'

RSpec.describe SimpleCov::Formatter::AIFormatter::MarkdownBuilder::ReportBudget do
  let(:buffer) { StringIO.new }
  let(:budget) { described_class.new(buffer, 1, 0) }

  def notice(deficit_files, bypass_files)
    described_class::TRUNCATION_ALERT_HEADING +
      format(described_class::TRUNCATION_ALERT_BODY, limit: 1, deficit_files: deficit_files, bypass_files: bypass_files)
  end

  def admissible_bytes(file_count)
    1000 - notice(file_count, file_count).bytesize - described_class::SEPARATOR_MARGIN
  end

  it 'admits fragments up to the ceiling minus the notice reserve and refuses the next byte unwritten' do
    admissions = [budget.admit('x' * admissible_bytes(0)), budget.admit('y')]
    expect([admissions, buffer.string.bytesize]).to eq([[true, false], admissible_bytes(0)])
  end

  it 'scales the ceiling with the configured limit' do
    two_kb = described_class.new(StringIO.new, 2, 0)
    fragment = 'x' * (admissible_bytes(0) + 1000)
    expect([two_kb.admit(fragment), two_kb.admit('y')]).to eq([true, false])
  end

  it 'writes the header and separators regardless of the budget' do
    budget.write('h' * 2000)
    expect(buffer.string.bytesize).to eq(2000)
  end

  it 'reserves room for the widest notice the file count allows' do
    wide = described_class.new(StringIO.new, 1, 10**9)
    fragment = 'x' * admissible_bytes(10**9)
    expect([wide.admit(fragment), wide.admit('y'), budget.admit("#{fragment}y")]).to eq([true, false, true])
  end

  it 'writes the notice with the omitted counts' do
    budget.write_notice(2, 1)
    expect(buffer.string).to eq(notice(2, 1))
  end
end
