# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require 'simplecov'
require 'parser/current'

require_relative 'simplecov-ai-formatter/version'
require_relative 'simplecov-ai-formatter/configuration'
require_relative 'simplecov-ai-formatter/ast_resolver'
require_relative 'simplecov-ai-formatter/markdown_builder'

module SimpleCov
  module Formatter
    class AIFormatter
      extend T::Sig

      sig { returns(SimpleCov::Formatter::AIFormatter::Configuration) }
      def self.configuration
        @configuration ||= T.let(Configuration.new, T.nilable(Configuration))
      end

      sig { params(block: T.nilable(T.proc.params(config: Configuration).void)).void }
      def self.configure
        yield(configuration) if block
      end

      sig { params(result: SimpleCov::Result).void }
      def format(result)
        config = self.class.configuration
        builder = MarkdownBuilder.new(result, config)
        digest = builder.build

        FileUtils.mkdir_p(File.dirname(config.report_path))
        File.write(config.report_path, digest)

        puts "\n[SimpleCov AI Formatter] Digest written to #{config.report_path}" if config.output_to_console
      end
    end
  end
end
