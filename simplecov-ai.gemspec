# Copyright (c) 2026 Vitalii Lazebnyi
# typed: strict
# frozen_string_literal: true

require 'openssl'

Gem::Specification.new do |spec|
  spec.name = 'simplecov-ai'
  # Read from lib/simplecov-ai/version.rb without loading the gem. The whole expression is the
  # right-hand side of `spec.version =`, which Dependabot replaces with a literal before it
  # evaluates the gemspec (it also stubs every File.read).
  spec.version = File.read(File.expand_path('lib/simplecov-ai/version.rb', __dir__))[/VERSION = '([^']+)'/, 1] or
    raise(
      Gem::InvalidSpecificationException,
      'Unable to parse VERSION from lib/simplecov-ai/version.rb; the constant definition may have changed'
    )
  spec.authors     = ['Vitalii Lazebnyi']
  spec.email       = ['vitalii.lazebnyi.github@gmail.com']
  spec.homepage    = 'https://github.com/VitaliiLazebnyi/simplecov-ai'
  spec.summary     = 'An AI-optimized Markdown formatter for SimpleCov utilizing AST mapping.'
  spec.description = 'Generates highly concise, deterministic Markdown coverage digests tailored ' \
    'for LLMs and autonomous agents by matching coverage deficits to their ' \
    'AST semantic boundaries rather than line numbers.'

  spec.license     = 'MIT'

  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata['bug_tracker_uri'] = "#{spec.homepage}/issues"
  spec.metadata['documentation_uri'] = 'https://rubydoc.info/gems/simplecov-ai'
  spec.metadata['allowed_push_host'] = 'https://rubygems.org'

  # Code signing is opt-in: set SIMPLECOV_AI_SIGN to any non-empty value (the release workflow
  # always does, and fails when the GEM_PRIVATE_KEY secret is missing). When enabled, the private key must
  # exist and must match the public certificate, otherwise the build aborts with a clear error
  # instead of producing a gem carrying a broken signature. When unset, the gem builds unsigned.
  if ENV['SIMPLECOV_AI_SIGN'].to_s.empty?
    # RubyGems signs with ~/.gem/gem-private_key.pem whenever that file exists, even though the
    # gemspec asked for nothing, and crashes or signs wrongly when that key belongs to a different
    # certificate. Point its default lookups at paths that cannot exist so that "unsigned" holds
    # on every machine, whatever lives in ~/.gem. The path is made absolute because `__dir__` is
    # `.` when the file is loaded as `Gem::Specification.load('simplecov-ai.gemspec')`.
    signing_disabled = File.expand_path('certs/signing-disabled', __dir__)
    %i[default_key_path default_cert_path].each do |lookup|
      # Removed before being redefined so `ruby -w` does not report a method redefinition.
      Gem.singleton_class.__send__(:remove_method, lookup) if Gem.singleton_class.method_defined?(lookup)
      Gem.define_singleton_method(lookup) { signing_disabled }
    end
  else
    cert_path = File.expand_path('certs/simplecov-ai-public_cert.pem', __dir__)
    private_key_path = File.expand_path('~/.gem/gem-private_key.pem')
    unless File.file?(private_key_path)
      raise(
        Gem::InvalidSpecificationException,
        "SIMPLECOV_AI_SIGN is set but no signing key exists at #{private_key_path}"
      )
    end

    certificate = OpenSSL::X509::Certificate.new(File.read(cert_path))
    private_key = OpenSSL::PKey.read(File.read(private_key_path))
    unless certificate.check_private_key(private_key)
      raise(
        Gem::InvalidSpecificationException,
        "The signing key at #{private_key_path} does not match #{cert_path}; refusing to build a wrongly signed gem"
      )
    end

    spec.cert_chain = [cert_path]
    spec.signing_key = private_key_path
  end

  # Requirements explicitly refined per updated SCAI-REQ-015
  spec.required_ruby_version = '>= 2.7.0'

  # Core execution footprint dependencies. `parser` is capped below 4 for the same reason as the
  # `simplecov < 2.0` ceiling below: the grammar table in lib/simplecov-ai/ast_resolver/parser_backend.rb
  # and the overlay in sorbet/rbi/parser.rbi only know the 3.x line.
  spec.add_dependency('parser', '>= 3.1.0', '< 4')
  spec.add_dependency('sorbet-runtime', '>= 0.5', '< 0.7')

  # SimpleCov floor per SCAI-REQ-016; upper-bounded below 2.0 because branch enrichment depends
  # on the internal branch-descriptor layout, which is only verified across the 0.18 to 1.x line.
  spec.add_dependency('simplecov', '>= 0.18', '< 2.0')

  # Gem files: glob relative to the gemspec directory (not the process CWD) and include only
  # regular files so directory entries are never packaged.
  spec.files = Dir.glob('{lib,certs}/**/*', base: __dir__)
    .select { |relative| File.file?(File.join(__dir__, relative)) } +
    ['LICENSE.txt', 'README.md']
  spec.require_paths = ['lib']
  spec.metadata['rubygems_mfa_required'] = 'true'
end
