# typed: strict
# frozen_string_literal: true

version_content = File.read(File.expand_path('lib/simplecov-ai/version.rb', __dir__))
version_match = version_content.match(/VERSION\s*=\s*T\.let\(['"]([^'"]+)['"],\s*String\)/)
version = version_match&.captures&.first or
  raise 'Unable to parse VERSION from lib/simplecov-ai/version.rb; the constant definition may have changed'

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
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata['allowed_push_host'] = 'https://rubygems.org'

  # Code signing configuration. Only advertise the certificate chain when a matching private
  # key is actually present, so unsigned local builds do not embed a dangling certificate path.
  cert_path = File.expand_path('certs/simplecov-ai-public_cert.pem', __dir__)
  private_key_path = File.expand_path('~/.gem/gem-private_key.pem')
  # Ensure the key file actually has substantial content (not just a newline from an empty secret)
  if File.exist?(cert_path) && File.exist?(private_key_path) && File.size(private_key_path) > 100
    spec.cert_chain = [cert_path]
    spec.signing_key = private_key_path
  end

  # Requirements explicitly refined per updated SCAI-REQ-015
  spec.required_ruby_version = '>= 2.7.0'

  # Core execution footprint dependencies
  spec.add_dependency 'parser', '>= 3.1.0'
  spec.add_dependency 'sorbet-runtime', '~> 0.5'

  # SimpleCov floor per SCAI-REQ-016; upper-bounded below 2.0 because branch enrichment depends
  # on the internal branch-descriptor layout, which is only verified across the 0.18–1.x line.
  spec.add_dependency 'simplecov', '>= 0.18', '< 2.0'

  # Development & testing dependencies that install on every supported Ruby and platform. The
  # Sorbet toolchain (sorbet, tapioca, rubocop-sorbet, standard-sorbet, yard-sorbet) lives in the
  # Gemfile because sorbet-static has no Windows, JRuby or TruffleRuby builds. Floors track the
  # newest release lines that still resolve on Ruby 2.7.
  spec.add_development_dependency 'base64'
  spec.add_development_dependency 'benchmark'
  spec.add_development_dependency 'bundler-audit', '~> 0.9.3'
  spec.add_development_dependency 'logger'
  spec.add_development_dependency 'ostruct'
  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rspec', '~> 3.13'
  spec.add_development_dependency 'rubocop', '~> 1.90'
  spec.add_development_dependency 'rubocop-packaging', '~> 0.6'
  spec.add_development_dependency 'rubocop-performance', '~> 1.27'
  spec.add_development_dependency 'rubocop-rake', '~> 0.7'
  spec.add_development_dependency 'rubocop-rspec', '~> 3.10'
  spec.add_development_dependency 'rubocop-thread_safety', '~> 0.7'
  spec.add_development_dependency 'tsort'
  spec.add_development_dependency 'yard', '~> 0.9.45'

  # Gem files: glob relative to the gemspec directory (not the process CWD) and include only
  # regular files so directory entries are never packaged.
  spec.files = Dir.glob('{lib,certs}/**/*', base: __dir__)
                  .select { |relative| File.file?(File.join(__dir__, relative)) } +
               ['LICENSE.txt', 'README.md']
  spec.require_paths = ['lib']
  spec.metadata['rubygems_mfa_required'] = 'true'
end
