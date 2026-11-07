# Copyright (c) 2026 Vitalii Lazebnyi
# typed: false
# frozen_string_literal: true

# The sources of the fixture project the end-to-end spec (spec/integration/end_to_end_spec.rb)
# writes and runs: the digest it expects quotes their exact lines.
module EndToEndSources
  # One covered method with a missed ternary arm, one never-invoked method with a repeated
  # statement, and one never-invoked method whose only line is a backtick command.
  CALC = <<~RUBY
    # frozen_string_literal: true

    module Shapes
      class Calc
        def sign(number)
          number.positive? ? :pos : :neg
        end

        def never_called
          @never = 1
          @never = 1
        end

        def shell
          `echo hi`
        end
      end
    end
  RUBY
  public_constant(:CALC)

  # Every bypass form: a nocov pair, an inline `simplecov:disable` and a `simplecov:disable
  # branch` block (the latter two are honoured by SimpleCov >= 1.0 only).
  LEGACY = <<~RUBY
    # frozen_string_literal: true

    module Shapes
      class Legacy
        #{SimpleCovFixtures::NOCOV_MARKER}
        def obsolete
          raise NotImplementedError
        end
        #{SimpleCovFixtures::NOCOV_MARKER}

        def fail_loudly
          raise 'x' # simplecov:disable
        end

        def pick(flag)
          # simplecov:disable branch
          flag ? :yes : :no
          # simplecov:enable branch
        end
      end
    end
  RUBY
  public_constant(:LEGACY)

  # A Struct.new block, a top-level nocov region and a top-level branch, so root-scope
  # attribution shows up for a deficit and for a bypass.
  POINT = <<~RUBY
    # frozen_string_literal: true

    Point = Struct.new(:x, :y) do
      def side
        x.positive? ? :right : :left
      end
    end

    #{SimpleCovFixtures::NOCOV_MARKER}
    DEBUG = ENV.key?('SHAPES_DEBUG')
    #{SimpleCovFixtures::NOCOV_MARKER}

    puts 'debugging' if DEBUG
  RUBY
  public_constant(:POINT)
end
