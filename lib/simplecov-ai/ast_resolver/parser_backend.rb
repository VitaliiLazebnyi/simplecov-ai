# typed: strong
# frozen_string_literal: true

require 'parser'
require_relative 'lenient_literals'

module SimpleCov
  module Formatter
    class AIFormatter
      class ASTResolver
        # Chooses the parsing backend once, at load time, and parses source buffers with it
        # without ever writing to STDERR (the diagnostics engine is given no consumer, so
        # warnings are dropped and only errors surface). Prism's `parser`-compatible translation
        # layer is preferred whenever it offers a grammar for the running Ruby (Ruby >= 3.3 with
        # Prism >= 1.2 and a `parser` gem recent enough for the translation to load); otherwise
        # the `parser` gem's own grammar for the running Ruby is loaded — its exact `parser/rubyXY`
        # grammar, or for a Ruby newer than any it ships the newest one, which is what
        # `parser/current` would load, minus the version-deviation warning `parser/current`
        # prints. Syntax errors surface as `Parser::SyntaxError`; warnings and non-fatal
        # diagnostics are dropped.
        module ParserBackend
          extend T::Sig

          # Prism releases below this predate the version-specific translation grammars this
          # backend selects (Ruby 3.4.0 bundles Prism 1.2.0).
          PRISM_MINIMUM_VERSION = '1.2.0'
          # Prism's translation layer refuses to load alongside older `parser` gems, so it is
          # only attempted when the installed gem satisfies that floor.
          PARSER_MINIMUM_FOR_PRISM = '3.3.7.2'

          # Prism's version-specific translation grammars keyed by Ruby major.minor, oldest first,
          # resolved lazily because the newer classes only exist in newer Prism releases. Rubies
          # older than the first are parsed by the `parser` gem, which ships an exact grammar for
          # each of them.
          PRISM_GRAMMARS = T.let(
            {
              '3.3' => -> { Prism::Translation::Parser33 },
              '3.4' => -> { Prism::Translation::Parser34 },
              '4.0' => -> { defined?(Prism::Translation::Parser40) ? Prism::Translation::Parser40 : nil },
              '4.1' => -> { defined?(Prism::Translation::Parser41) ? Prism::Translation::Parser41 : nil }
            }.freeze,
            T::Hash[String, T.proc.returns(T.nilable(T.class_of(Parser::Base)))]
          )

          # The `parser` gem's grammars keyed by Ruby major.minor, oldest first, resolved lazily
          # so only the grammar for the running Ruby is ever loaded.
          PARSER_GEM_GRAMMARS = T.let(
            {
              '2.7' => -> { Parser::Ruby27 },
              '3.0' => -> { Parser::Ruby30 },
              '3.1' => -> { Parser::Ruby31 },
              '3.2' => -> { Parser::Ruby32 },
              '3.3' => -> { Parser::Ruby33 },
              '3.4' => -> { Parser::Ruby34 }
            }.freeze,
            T::Hash[String, T.proc.returns(T.class_of(Parser::Base))]
          )

          # Picks the grammar class used to parse every file in this process.
          #
          # @param ruby_version [String] The Ruby version to match a grammar against.
          # @param parser_version [String] The installed `parser` gem version.
          # @return [Class] A `Parser::Base` subclass.
          # @raise [LoadError] When neither Prism nor the `parser` gem has a grammar for a Ruby
          #   this old (older than every supported Ruby).
          sig { params(ruby_version: String, parser_version: String).returns(T.class_of(Parser::Base)) }
          def self.select_grammar(ruby_version: RUBY_VERSION, parser_version: Parser::VERSION)
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
            parser.builder.extend(LenientLiterals)
            parser.diagnostics.all_errors_are_fatal = true
            parser.parse(buffer)
          end

          # Prism's translation grammar for the running Ruby — the version-specific class when
          # Prism ships one, else the base class parsing with Prism's newest grammar — or nil
          # when Prism cannot be used: a Ruby older than its oldest grammar, a `parser` gem too
          # old for the translation layer, or a missing/too-old Prism.
          sig do
            params(ruby_version: String, parser_version: String).returns(T.nilable(T.class_of(Parser::Base)))
          end
          def self.prism_grammar(ruby_version, parser_version)
            return nil if below?(ruby_version, PRISM_GRAMMARS.keys.fetch(0))
            return nil if below?(parser_version, PARSER_MINIMUM_FOR_PRISM)
            return nil unless prism_translation_loaded?

            PRISM_GRAMMARS[major_minor(ruby_version)]&.call || Prism::Translation::Parser
          end

          # Loads Prism's translation layer when the installed Prism is recent enough to ship
          # it (Ruby 3.3's bundled Prism 0.19 has none).
          sig { returns(T::Boolean) }
          def self.prism_translation_loaded?
            require 'prism'
            return false if below?(Prism::VERSION, PRISM_MINIMUM_VERSION)

            require 'prism/translation/parser'
            true
          rescue LoadError
            false
          end

          # The `parser` gem grammar for the running Ruby: the newest `parser/rubyXY` grammar
          # the installed gem ships that is not newer than the running Ruby.
          sig { params(ruby_version: String).returns(T.class_of(Parser::Base)) }
          def self.parser_gem_grammar(ruby_version)
            PARSER_GEM_GRAMMARS.reverse_each do |series, grammar|
              next if below?(ruby_version, series)
              return grammar.call if loadable?("parser/ruby#{series.delete('.')}")
            end
            raise LoadError, "the parser gem ships no grammar for Ruby #{ruby_version}"
          end

          sig { params(feature: String).returns(T::Boolean) }
          def self.loadable?(feature)
            require feature
            true
          rescue LoadError
            false
          end

          # Compares dotted version strings as RubyGems does: "3.3" and "3.3.0" are equal, and
          # "3.3" is below "3.3.7.2".
          sig { params(version: String, floor: String).returns(T::Boolean) }
          def self.below?(version, floor)
            Gem::Version.new(floor) > version
          end

          sig { params(ruby_version: String).returns(String) }
          def self.major_minor(ruby_version)
            Gem::Version.new(ruby_version).segments.first(2).join('.')
          end

          private_class_method :prism_grammar, :prism_translation_loaded?, :parser_gem_grammar, :loadable?,
                               :below?, :major_minor

          # The grammar class selected for this process.
          GRAMMAR = T.let(select_grammar, T.class_of(Parser::Base))
        end
      end
    end
  end
end
