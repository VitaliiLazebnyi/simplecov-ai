# typed: strict
# frozen_string_literal: true

require 'parser'
require_relative 'lenient_literals'

module SimpleCov
  module Formatter
    class AIFormatter
      class ASTResolver
        # Chooses the parsing backend once, at load time, and parses source buffers with it
        # without ever writing to STDERR (the diagnostics engine is given no consumer, so
        # warnings are dropped and only errors surface). Prism's `parser`-compatible translation layer is
        # preferred whenever it offers a grammar for the running Ruby (Ruby >= 3.3 with
        # Prism >= 1.2 and a `parser` gem recent enough for the translation to load); otherwise
        # the `parser` gem's exact grammar for the running Ruby is loaded, falling back to
        # `parser/current` with its version-deviation warning muted. Syntax errors surface as
        # `Parser::SyntaxError`; warnings and non-fatal diagnostics are dropped.
        module ParserBackend
          extend T::Sig

          # Prism releases below this predate the version-specific translation grammars this
          # backend selects (Ruby 3.4.0 bundles Prism 1.2.0).
          PRISM_MINIMUM_VERSION = T.let('1.2.0', String)
          # Prism's translation layer refuses to load alongside older `parser` gems, so it is
          # only attempted when the installed gem satisfies that floor.
          PARSER_MINIMUM_FOR_PRISM = T.let('3.3.7.2', String)
          # The oldest Ruby grammar Prism implements; older Rubies are parsed by the `parser`
          # gem, which ships an exact grammar for each of them.
          PRISM_OLDEST_GRAMMAR = T.let('3.3', String)
          # The `parser` gem grammar loaded when no exact grammar exists for the running Ruby.
          FALLBACK_GRAMMAR_FEATURE = T.let('parser/current', String)

          # Prism's version-specific translation grammars keyed by Ruby major/minor, resolved
          # lazily because the newer classes only exist in newer Prism releases.
          PRISM_GRAMMARS = T.let(
            {
              '33' => -> { Prism::Translation::Parser33 },
              '34' => -> { Prism::Translation::Parser34 },
              '40' => -> { defined?(Prism::Translation::Parser40) ? Prism::Translation::Parser40 : nil },
              '41' => -> { defined?(Prism::Translation::Parser41) ? Prism::Translation::Parser41 : nil }
            }.freeze,
            T::Hash[String, T.proc.returns(T.nilable(T.class_of(Parser::Base)))]
          )

          # The `parser` gem's exact grammars keyed by Ruby major/minor, resolved lazily so only
          # the grammar for the running Ruby is ever loaded.
          PARSER_GEM_GRAMMARS = T.let(
            {
              '27' => -> { Parser::Ruby27 },
              '30' => -> { Parser::Ruby30 },
              '31' => -> { Parser::Ruby31 },
              '32' => -> { Parser::Ruby32 },
              '33' => -> { Parser::Ruby33 },
              '34' => -> { Parser::Ruby34 }
            }.freeze,
            T::Hash[String, T.proc.returns(T.class_of(Parser::Base))]
          )

          # Picks the grammar class used to parse every file in this process.
          #
          # @param ruby_version [String] The Ruby version to match a grammar against.
          # @param parser_version [String] The installed `parser` gem version.
          # @return [Class] A `Parser::Base` subclass.
          sig { params(ruby_version: String, parser_version: String).returns(T.class_of(Parser::Base)) }
          def self.select_grammar(ruby_version: RUBY_VERSION, parser_version: T.let(Parser::VERSION, String))
            prism_grammar(ruby_version, parser_version) || parser_gem_grammar(ruby_version)
          end

          # Parses a source buffer with the selected grammar, raising on syntax errors, dropping
          # warnings and accepting the literals MRI accepts (see {LenientLiterals}).
          #
          # @param buffer [Parser::Source::Buffer] The source to parse.
          # @return [Parser::AST::Node, nil] The root AST node, or nil for an empty or
          #   comment-only source.
          # @raise [Parser::SyntaxError] When the source is not valid Ruby.
          sig { params(buffer: Parser::Source::Buffer).returns(T.nilable(Parser::AST::Node)) }
          def self.parse(buffer)
            parser = GRAMMAR.new
            T.cast(parser.builder, Parser::Builders::Default).extend(LenientLiterals)
            T.cast(parser.diagnostics, Parser::Diagnostic::Engine).all_errors_are_fatal = true
            T.cast(parser.parse(buffer), T.nilable(Parser::AST::Node))
          end

          # Prism's translation grammar for the running Ruby — the version-specific class when
          # Prism ships one, else the base class parsing with Prism's newest grammar — or nil
          # when Prism cannot be used: a Ruby older than its oldest grammar, a `parser` gem too
          # old for the translation layer, or a missing/too-old Prism.
          sig do
            params(ruby_version: String, parser_version: String).returns(T.nilable(T.class_of(Parser::Base)))
          end
          def self.prism_grammar(ruby_version, parser_version)
            return nil if below?(ruby_version, PRISM_OLDEST_GRAMMAR)
            return nil if below?(parser_version, PARSER_MINIMUM_FOR_PRISM)
            return nil unless prism_translation_loaded?

            PRISM_GRAMMARS[major_minor(ruby_version)]&.call || Prism::Translation::Parser
          end

          # Loads Prism's translation layer when the installed Prism is recent enough to ship
          # it (Ruby 3.3's bundled Prism 0.19 has none).
          sig { returns(T::Boolean) }
          def self.prism_translation_loaded?
            require 'prism'
            return false if below?(T.let(Prism::VERSION, String), PRISM_MINIMUM_VERSION)

            require 'prism/translation/parser'
            true
          rescue LoadError
            false
          end

          # The `parser` gem grammar for the running Ruby: the exact `parser/rubyXY` grammar when
          # the gem ships one, else `parser/current` (its newest grammar) loaded with the
          # version-deviation warning muted so consumers never see it.
          sig { params(ruby_version: String).returns(T.class_of(Parser::Base)) }
          def self.parser_gem_grammar(ruby_version)
            ruby_series = major_minor(ruby_version)
            grammar = PARSER_GEM_GRAMMARS[ruby_series]
            return grammar.call if grammar && loadable?("parser/ruby#{ruby_series}")

            silence_warnings { require FALLBACK_GRAMMAR_FEATURE }
            Parser::CurrentRuby
          end

          sig { params(feature: String).returns(T::Boolean) }
          def self.loadable?(feature)
            require feature
            true
          rescue LoadError
            false
          end

          sig { params(blk: T.proc.void).void }
          def self.silence_warnings(&blk)
            previous_verbosity = $VERBOSE
            $VERBOSE = nil
            yield
          ensure
            $VERBOSE = previous_verbosity
          end

          # Compares dotted version strings numerically, segment by segment: a version with fewer
          # segments than the floor is padded with zeros (so "3.3" and "3.3.0" are equal), and
          # segments beyond the floor's length cannot make a version lower.
          sig { params(version: String, floor: String).returns(T::Boolean) }
          def self.below?(version, floor)
            version_segments = numeric_segments(version)
            orderings = numeric_segments(floor).each_with_index.map do |floor_segment, index|
              version_segments.at(index).to_i <=> floor_segment
            end
            orderings.find { |ordering| !ordering.zero? } == -1
          end

          sig { params(version: String).returns(T::Array[Integer]) }
          def self.numeric_segments(version)
            version.split('.').map(&:to_i)
          end

          sig { params(ruby_version: String).returns(String) }
          def self.major_minor(ruby_version)
            numeric_segments(ruby_version).first(2).join
          end

          private_class_method :prism_grammar, :prism_translation_loaded?, :parser_gem_grammar, :loadable?,
                               :silence_warnings, :below?, :numeric_segments, :major_minor

          # The grammar class selected for this process.
          GRAMMAR = T.let(select_grammar, T.class_of(Parser::Base))
        end
      end
    end
  end
end
