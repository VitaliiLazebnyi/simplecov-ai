# Copyright (c) 2026 Vitalii Lazebnyi
# typed: strong
# frozen_string_literal: true

module SimpleCov
  module Formatter
    class AIFormatter
      class Configuration
        # The values behind the readers. The props check each value's type on assignment
        # (TypeError); the writers of {Configuration} check its domain first. The props declare
        # no `default:` - sorbet-runtime's default machinery fails on JRuby - so
        # {Configuration#initialize} passes every default; the report path is left unset (nil).
        class Settings < T::Struct
          prop :report_path, T.nilable(String)
          prop :max_file_size_kb, Integer
          prop :max_snippet_lines, Integer
          prop :output_to_console, T::Boolean
          prop :granularity, Symbol
          prop :include_bypasses, T::Boolean
        end
      end
    end
  end
end
