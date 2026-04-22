# typed: strict
# frozen_string_literal: true

version_content = File.read(File.expand_path('lib/simplecov-ai/version.rb', __dir__))
version_match = version_content.match(/VERSION\s*=\s*T\.let\(['"]([^'"]+)['"],\s*String\)/)
version = version_match ? version_match[1] : '0.0.0'

Gem::Specification.new do |spec|
  spec.name        = 'simplecov-ai'
  spec.version     = version
  spec.authors     = ['Vitalii Lazebnyi']
  spec.email       = ['vitalii.lazebnyi.github@gmail.com']
  spec.homepage    = 'https://github.com/VitaliiLazebnyi/simplecov-ai'
  spec.summary     = 'An AI-optimized Markdown formatter for SimpleCov utilizing AST mapping.'
  spec.description = 'Generates highly concise, deterministic Markdown coverage digests tailored ' \
                     'for LLMs and autonomous agents by matching coverage deficits to their ' \
                     'AST semantic boundaries rather than line numbers.'

  spec.license     = 'MIT'

  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['allowed_push_host'] = 'https://rubygems.org'

  # Code signing configuration
  cert_path = File.expand_path('certs/simplecov-ai-public_cert.pem', __dir__)
  if File.exist?(cert_path)
    spec.cert_chain = [cert_path]
    private_key_path = File.expand_path('~/.gem/gem-private_key.pem')
    # Ensure the key file actually has substantial content (not just a newline from an empty secret)
    if File.exist?(private_key_path) && File.size(private_key_path) > 100
      spec.signing_key = private_key_path
    end
  end

  # Requirements explicitly refined per updated SCMD-REQ-015
  spec.required_ruby_version = '>= 3.0.0'

  # Core execution footprint dependencies
  spec.add_dependency 'parser', '>= 3.1.0'
  spec.add_dependency 'sorbet-runtime', '~> 0.5'

  # Ensure SimpleCov is available and meets the hard minimum SCMD-REQ-016
  spec.add_dependency 'simplecov', '>= 0.18.0'

  # Development & Testing framework expectations
  spec.add_development_dependency 'base64'
  spec.add_development_dependency 'benchmark'
  spec.add_development_dependency 'logger'
  spec.add_development_dependency 'ostruct'
  spec.add_development_dependency 'rspec', '~> 3.12'
  spec.add_development_dependency 'rubocop', '~> 1.28'
  spec.add_development_dependency 'rubocop-performance', '~> 1.14'
  spec.add_development_dependency 'rubocop-rspec', '~> 2.11'
  spec.add_development_dependency 'rubocop-thread_safety'
  spec.add_development_dependency 'sorbet', '~> 0.5'
  spec.add_development_dependency 'tsort'
  spec.add_development_dependency 'yard'
  spec.add_development_dependency 'yard-sorbet'

  # Gem files (strict native globbing)
  spec.files = Dir.glob('{lib,certs}/**/*') + ['LICENSE.txt', 'README.md']
  spec.require_paths = ['lib']
  spec.metadata['rubygems_mfa_required'] = 'true'
end
