# typed: true
# frozen_string_literal: true

# Extra requires evaluated before `bin/tapioca gem` reflects on the bundle, so that constants
# the library depends on but which the gems do not load by default are present in the RBIs:
# `Parser::CurrentRuby` (parser/current), the prism -> parser translation layer, and SimpleCov.
require 'parser/current'
require 'prism'
require 'prism/translation/parser'
require 'simplecov'
