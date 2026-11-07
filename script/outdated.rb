#!/usr/bin/env ruby
# Copyright (c) 2026 Vitalii Lazebnyi
# typed: strict
# frozen_string_literal: true

require 'json'
require 'net/http'
require 'open3'
require 'sorbet-runtime'
require 'yaml'

# Fails when anything in the toolchain is behind its newest release without being on the
# documented hold list (script/outdated_holds.yml), or when a listed hold is no longer needed:
#
# - every gem of the bundle (`bundle outdated`);
# - the Ruby of .ruby-version (the newest stable release), every exact Ruby of the CI workflows
#   (the newest patch release of its series) and the mutation Ruby hold;
# - every GitHub Action, pinned to the commit of its newest release tag;
# - the tools the workflows download (actionlint, editorconfig-checker, gitleaks, lychee,
#   ShellCheck, shfmt), the Semgrep image and the digest every image is pinned to;
# - the npm packages of package.json, the pip packages of .github/python/requirements.txt and the
#   Node.js release of .node-version.
module Outdated
  extend T::Sig

  ROOT = T.let(File.expand_path('..', __dir__), String)
  private_constant(:ROOT)

  # Newest releases, as published upstream.
  module Upstream
    extend T::Sig

    # Release tags of the form `1.2.3`, `v1.2.3` or (lychee) `lychee-v1.2.3`, optionally peeled
    # (`^{}`).
    RELEASE_TAG = %r{\Arefs/tags/((?:lychee-)?v?\d+\.\d+\.\d+)(\^\{\})?\z}.freeze
    private_constant(:RELEASE_TAG)
    # The repositories endpoint of the Docker Hub API.
    DOCKER_HUB = 'https://hub.docker.com/v2/repositories'
    private_constant(:DOCKER_HUB)

    # @param text [String] A version, optionally prefixed with `v` or `lychee-v`.
    # @return [Gem::Version] The version.
    sig { params(text: String).returns(Gem::Version) }
    def self.version(text)
      Gem::Version.new(text.delete_prefix('lychee-').delete_prefix('v'))
    end

    # @param url [String] A JSON API endpoint.
    # @return [Object] The parsed response.
    sig { params(url: String).returns(BasicObject) }
    def self.json(url)
      JSON.parse(Net::HTTP.get(URI(url)).to_s)
    end

    # @param name [String] An npm package.
    # @return [String] Its newest release.
    sig { params(name: String).returns(String) }
    def self.npm(name)
      Hash.try_convert(json("https://registry.npmjs.org/#{name}/latest")).to_h.fetch('version').to_s
    end

    # @param name [String] A PyPI package.
    # @return [String] Its newest release.
    sig { params(name: String).returns(String) }
    def self.pypi(name)
      Hash.try_convert(json("https://pypi.org/pypi/#{name}/json")).to_h.fetch('info').fetch('version').to_s
    end

    # @param major [String] A Node.js major version.
    # @return [String] The newest release of that major line.
    sig { params(major: String).returns(String) }
    def self.node(major)
      index = JSON.parse(Net::HTTP.get(URI('https://nodejs.org/dist/index.json')).to_s)
      releases = index.map { |release| release.fetch('version').to_s }
      line = releases.grep(/\Av#{major}\./)
      newest = line.max_by { |release| version(release) }
      newest.to_s.delete_prefix('v')
    end

    # The newest release tag of a GitHub repository and the commit it points to: an annotated
    # tag lists its commit under `tag^{}` (after the tag object, so it wins), a lightweight tag
    # only under `tag`.
    sig { params(repository: String).returns([String, String]) }
    def self.tag(repository)
      refs, status = Open3.capture2('git', 'ls-remote', '--tags', "https://github.com/#{repository}")
      abort("git ls-remote #{repository} failed") unless status.success?
      tags = refs.lines.filter_map { |line| tag_entry(line) }
      newest = tags.map(&:first).max_by { |tag| version(tag) }
        .to_s
      [newest, tags.to_h.fetch(newest)]
    end

    # The release tag and commit of one line of `git ls-remote --tags`.
    #
    # @param line [String] The line.
    # @return [Array(String, String), nil] The tag and commit; nil for a ref that is no release tag.
    sig { params(line: String).returns(T.nilable([String, String])) }
    def self.tag_entry(line)
      commit, ref = line.split
      match = RELEASE_TAG.match(ref.to_s)
      [match[1].to_s, commit.to_s] if match
    end

    # @return [Array<Gem::Version>] Every Ruby release.
    sig { returns(T::Array[Gem::Version]) }
    def self.rubies
      index = Net::HTTP.get(URI('https://cache.ruby-lang.org/pub/ruby/index.txt')).to_s
      index.scan(/^ruby-\K\d+\.\d+\.\d+(?=\s)/).map { |release| version(release.to_s) }
    end

    # What is wrong with an image pin: a digest its tag no longer points to (an official image
    # lives under `library/` on Docker Hub), or a Semgrep release that is not the newest.
    sig { params(repository: String, tag: String, digest: String).returns(T::Array[String]) }
    def self.image_problems(repository, tag, digest)
      path = repository.include?('/') ? repository : "library/#{repository}"
      current = JSON.parse(Net::HTTP.get(URI("#{DOCKER_HUB}/#{path}/tags/#{tag}")).to_s).fetch('digest')
      newest = repository == 'semgrep/semgrep' ? semgrep : tag
      [
        ("image #{repository}:#{tag} is pinned to #{digest}, not #{current}" if digest != current),
        ("image #{repository}:#{tag} is not the newest release #{newest}" if tag != newest)
      ].compact
    end

    # @return [String] The newest Semgrep release published on Docker Hub.
    sig { returns(String) }
    def self.semgrep
      tags = JSON.parse(Net::HTTP.get(URI("#{DOCKER_HUB}/semgrep/semgrep/tags?page_size=100")).to_s)
      names = tags.fetch('results').map { |tag| tag.fetch('name') }
        .grep(/\A\d+\.\d+\.\d+\z/)
      names.max_by { |name| version(name) }
        .to_s
    end
  end

  # The gem holds of the hold list against `bundle outdated`.
  class GemHolds
    extend T::Sig

    # One line of `bundle outdated --parseable`.
    OUTDATED_LINE = /\A(\S+) \(newest ([^,\s]+), installed ([^,)\s]+)/.freeze
    private_constant(:OUTDATED_LINE)

    # `bundle outdated` refuses to run in deployment mode, which `ruby/setup-ruby`'s bundler cache
    # turns on; it exits 1 when it reports an outdated gem, and with any other failure status
    # when it could not check at all.
    ENV_OVERRIDES = T.let(
      { 'BUNDLE_DEPLOYMENT' => 'false', 'BUNDLE_FROZEN' => 'false' }.freeze, T::Hash[String, String]
    )
    private_constant(:ENV_OVERRIDES)

    # @return [Array<Array(String, String, String)>] Name, newest and installed version of every
    #   outdated gem.
    sig { returns(T::Array[[String, String, String]]) }
    def self.outdated
      output, status = Open3.capture2e(ENV_OVERRIDES, 'bundle', 'outdated', '--parseable', chdir: ROOT)
      abort("bundle outdated failed:\n#{output}") unless [0, 1].include?(status.exitstatus)
      output.lines.filter_map do |line|
        match = OUTDATED_LINE.match(line)
        [match[1].to_s, match[2].to_s, match[3].to_s] if match
      end
    end

    sig { params(holds: BasicObject).void }
    def initialize(holds)
      @newest_by_gem = T.let(
        Hash.try_convert(holds).to_h.transform_values { |hold| hold.fetch('newest').to_s },
        T::Hash[String, String]
      )
    end

    # @return [String, nil] The problem with an outdated gem, nil when it is held at that release.
    sig { params(name: String, newest: String, installed: String).returns(T.nilable(String)) }
    def problem(name, newest, installed)
      on_hold = @newest_by_gem[name] == newest
      puts("gem #{name} #{installed} -> #{newest}#{' (on hold)' if on_hold}")
      "gem #{name} #{installed} -> #{newest} is not on the hold list" unless on_hold
    end

    # @return [Array<String>] The held gems that are no longer outdated.
    sig { params(outdated: T::Array[String]).returns(T::Array[String]) }
    def stale(outdated)
      @newest_by_gem.keys - outdated
    end
  end

  # Collects the problems of every check, printing each as it is found.
  class Problems
    extend T::Sig

    sig { void }
    def initialize
      @messages = T.let([], T::Array[String])
    end

    # @param message [String] The problem.
    # @return [void]
    sig { params(message: String).void }
    def add(message)
      @messages << message
      warn("OUTDATED: #{message}")
    end

    # @return [Integer] The number of problems found.
    sig { returns(Integer) }
    def count
      @messages.size
    end

    # @return [Boolean] Whether no problem was found.
    sig { returns(T::Boolean) }
    def empty?
      @messages.empty?
    end
  end

  # The bundle and the Rubies: the gems against their holds, .ruby-version, every exact CI Ruby and
  # the mutation Ruby hold.
  class Check
    extend T::Sig

    # A Ruby version of a workflow: `ruby-version: 3.4.12`, or the expected version passed to
    # script/check_ruby.sh.
    RUBY_VERSION_PATTERN = /(?:ruby-version: |check_ruby\.sh )\K\d+\.\d+\.\d+\b/.freeze
    private_constant(:RUBY_VERSION_PATTERN)
    # A `ruby: [3.3.13, 3.4.12]` matrix (whose MRI entries are exact versions).
    RUBY_MATRIX_PATTERN = /^\s*ruby: \[([^\]]*)\]/.freeze
    private_constant(:RUBY_MATRIX_PATTERN)

    sig { params(problems: Problems, workflows: T::Hash[String, String]).void }
    def initialize(problems, workflows)
      @problems = problems
      @workflows = workflows
      @holds = T.let(YAML.safe_load_file(File.join(ROOT, 'script', 'outdated_holds.yml')), T::Hash[String, BasicObject])
    end

    # Runs the bundle and Ruby checks.
    #
    # @return [void]
    sig { void }
    def run
      gems
      rubies
      mutation_ruby
    end

    private

    sig { returns(Gem::Version) }
    def lockfile_ruby
      Upstream.version(File.read(File.join(ROOT, '.ruby-version')).strip)
    end

    # Gems: the parseable `bundle outdated` report against the gem holds.
    sig { void }
    def gems
      gem_holds = GemHolds.new(@holds.fetch('gems'))
      outdated = GemHolds.outdated
      outdated.each do |name, newest, installed|
        gem_holds.problem(name, newest, installed)&.then { |text| @problems.add(text) }
      end
      gem_holds.stale(outdated.map(&:first)).each do |name|
        @problems.add("gem hold #{name} is stale: no longer outdated")
      end
    end

    # Ruby: .ruby-version is the newest stable release, every exact CI Ruby the newest of its series.
    sig { void }
    def rubies
      releases = Upstream.rubies
      newest = releases.max
      @problems.add(".ruby-version #{lockfile_ruby} is not the newest Ruby #{newest}") if lockfile_ruby != newest
      @workflows.each do |name, text|
        ruby_versions(text).each { |ruby| newest_of_series(name, ruby, releases) }
      end
    end

    sig { params(text: String).returns(T::Array[String]) }
    def ruby_versions(text)
      matrix = text.scan(RUBY_MATRIX_PATTERN).flat_map { |list| list.to_s.split(', ') }
      versions = text.scan(RUBY_VERSION_PATTERN).map(&:to_s) + matrix.grep(/\A\d+\.\d+\.\d+\z/)
      versions.uniq
    end

    sig { params(name: String, ruby: String, releases: T::Array[Gem::Version]).void }
    def newest_of_series(name, ruby, releases)
      series = Upstream.version(ruby).segments.first(2)
      newest = releases.select { |release| release.segments.first(2) == series }
        .max
      return if Upstream.version(ruby) == newest

      @problems.add("#{name}: Ruby #{ruby} is not the newest of its series, #{newest}")
    end

    # The mutation Ruby hold is still needed: mutant still loads parser/current, which still has
    # no grammar for the Ruby of .ruby-version; and the mutation workflow runs on the held Ruby.
    sig { void }
    def mutation_ruby
      series = lockfile_ruby.segments.first(2).join('\\.')
      @problems.add('mutation Ruby hold is stale: mutant no longer requires parser/current') unless
        gem_file('mutant', 'lib/mutant.rb').include?('parser/current')
      @problems.add('mutation Ruby hold is stale: parser/current has a grammar for .ruby-version') if
        gem_file('parser', 'lib/parser/current.rb').include?("/^#{series}\\./")
      hold = @holds.fetch('mutation_ruby')
      @problems.add("mutation.yml does not run on the held Ruby #{hold}") unless
        @workflows.fetch('mutation.yml').include?("ruby-version: #{hold}")
    end

    sig { params(gem: String, path: String).returns(String) }
    def gem_file(gem, path)
      File.read(File.join(Gem.loaded_specs.fetch(gem).full_gem_path, path))
    end
  end

  # Everything the workflows and the npm and pip tooling pin: the Actions, the downloaded tools, the
  # container images, the npm packages, the pip packages and the Node.js release.
  class Pins
    extend T::Sig

    # The repositories of the tools the workflows download, by their `<NAME>_VERSION` variable.
    TOOLS = T.let(
      {
        'ACTIONLINT' => 'rhysd/actionlint',
        'EDITORCONFIG_CHECKER' => 'editorconfig-checker/editorconfig-checker',
        'GITLEAKS' => 'gitleaks/gitleaks',
        'LYCHEE' => 'lycheeverse/lychee',
        'SHELLCHECK' => 'koalaman/shellcheck',
        'SHFMT' => 'mvdan/sh'
      }.freeze,
      T::Hash[String, String]
    )
    private_constant(:TOOLS)

    sig { params(problems: Problems, workflows: T::Hash[String, String]).void }
    def initialize(problems, workflows)
      @problems = problems
      @workflows = workflows
    end

    # Runs the pin checks.
    #
    # @return [void]
    sig { void }
    def run
      actions
      tools
      images
      npm_packages
      pip_packages
      node
    end

    private

    # GitHub Actions: `uses: owner/repo[/path]@<sha>  # <tag>` names the newest tag, pinned to its commit.
    sig { void }
    def actions
      @workflows.each do |name, text|
        text.scan(%r{uses: ([\w.-]+/[\w.-]+)[\w./-]*@(\h{40}) +# (\S+)}).uniq.each do |repository, commit, tag|
          newest = Upstream.tag(repository.to_s)
          @problems.add("#{name}: #{repository} #{tag} (#{commit}) is not #{newest.join(' ')}") if [
            tag,
            commit
          ] != newest
        end
      end
    end

    # Downloaded tools (`<NAME>_VERSION: x.y.z`) are at their newest release.
    sig { void }
    def tools
      @workflows.each do |name, text|
        text.scan(/\b(#{TOOLS.keys.join('|')})_VERSION: (\S+)/o).uniq.each do |tool, pinned|
          newest, = Upstream.tag(TOOLS.fetch(tool.to_s))
          next if Upstream.version(newest) == Upstream.version(pinned.to_s)

          @problems.add("#{name}: #{tool} #{pinned} is not the newest #{newest}")
        end
      end
    end

    # Every container image (`<NAME>_IMAGE: repository:tag@sha256:...`) is pinned to the digest its
    # tag points to now; the Semgrep image is also its newest release.
    sig { void }
    def images
      @workflows.each do |name, text|
        text.scan(%r{_IMAGE: ([\w./-]+):([\w.-]+)@(sha256:\h+)}).uniq.each do |repository, tag, digest|
          Upstream.image_problems(repository.to_s, tag.to_s, digest.to_s).each do |message|
            @problems.add("#{name}: #{message}")
          end
        end
      end
    end

    # npm: every package package.json pins (its dependencies and the overrides of transitive ones)
    # is at its newest release.
    sig { void }
    def npm_packages
      package = JSON.parse(File.read(File.join(ROOT, 'package.json')))
      package.fetch('devDependencies').merge(package.fetch('overrides', {})).each do |name, pinned|
        newest = Upstream.npm(name)
        @problems.add("npm package #{name} #{pinned} is not the newest #{newest}") if pinned != newest
      end
    end

    # pip: every package .github/python/requirements.txt pins is at its newest release.
    sig { void }
    def pip_packages
      requirements = File.read(File.join(ROOT, '.github', 'python', 'requirements.txt'))
      requirements.scan(/^([\w.-]+)==(\S+)/).each do |name, pinned|
        newest = Upstream.pypi(name.to_s)
        @problems.add("pip package #{name} #{pinned} is not the newest #{newest}") if pinned != newest
      end
    end

    # Node.js: .node-version is the newest release of its major line.
    sig { void }
    def node
      pinned = File.read(File.join(ROOT, '.node-version')).strip
      newest = Upstream.node(Upstream.version(pinned).segments.fetch(0).to_s)
      @problems.add(".node-version #{pinned} is not the newest of its major line, #{newest}") if pinned != newest
    end
  end

  # Runs every check and reports whether all passed.
  #
  # @return [Boolean] Whether nothing is outdated.
  sig { returns(T::Boolean) }
  def self.passed?
    problems = Problems.new
    paths = Dir[File.join(ROOT, '.github', 'workflows', '*.yml')]
    workflows = paths.to_h { |path| [File.basename(path), File.read(path)] }
    Check.new(problems, workflows).run
    Pins.new(problems, workflows).run
    return true if problems.empty?

    warn("#{problems.count} problem(s)")
    false
  end
end

exit(Outdated.passed?)
