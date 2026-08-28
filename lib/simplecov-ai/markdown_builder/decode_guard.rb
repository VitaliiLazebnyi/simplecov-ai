# typed: strict
# frozen_string_literal: true

module SimpleCov
  module Formatter
    class AIFormatter
      class MarkdownBuilder
        # Contains the errors SimpleCov raises while it materialises a file's coverage data from
        # a corrupt resultset, so one undecodable file degrades to an error entry and the rest of
        # the report is still produced (SCAI-REQ-011). SimpleCov < 1.0 decodes the stringified
        # branch descriptors of a merged result with `eval`, so a malformed descriptor raises
        # `SyntaxError` — a `ScriptError`, which a `StandardError` rescue lets through and which
        # would otherwise abort the whole at_exit report; SimpleCov >= 1.0's `RubyDataParser`
        # raises `ArgumentError` instead, and malformed hit counts or line arrays fail with
        # whatever `NoMethodError` or `TypeError` they provoke. `SyntaxError` is the only
        # `ScriptError` contained: a `NotImplementedError` or `LoadError` is a defect, not
        # undecodable data, and propagates.
        module DecodeGuard
          extend T::Sig

          # Entry standing in for the deficits or bypasses of a file whose coverage data could
          # not be decoded; the placeholder names the error class SimpleCov raised.
          ERROR_TEMPLATE = T.let(
            "  - **ERROR:** SimpleCov could not decode this file's coverage data (%s); skipped.\n", String
          )

          # Runs a computation over SimpleCov's coverage objects.
          #
          # @param fallback [Object] The value to use when SimpleCov cannot decode the data.
          # @yield Reads or derives something from SimpleCov's coverage objects.
          # @return [Object] The block's value, or `fallback` when the block raised while decoding.
          sig do
            type_parameters(:Value)
              .params(fallback: T.type_parameter(:Value), blk: T.proc.returns(T.type_parameter(:Value)))
              .returns(T.type_parameter(:Value))
          end
          def self.attempt(fallback, &blk)
            yield
          rescue StandardError, SyntaxError
            fallback
          end

          # Renders the Markdown fragments of one file from SimpleCov's coverage objects.
          #
          # @yield Renders the file's fragments.
          # @return [Array<String>] The rendered fragments, or the single error entry naming the
          #   error SimpleCov raised while decoding the file's data.
          sig { params(blk: T.proc.returns(T::Array[String])).returns(T::Array[String]) }
          def self.render(&blk)
            yield
          rescue StandardError, SyntaxError => error
            [format(ERROR_TEMPLATE, error.class)]
          end
        end
      end
    end
  end
end
