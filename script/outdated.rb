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
#   ShellCheck, shfmt, Trivy), the Semgrep image and the digest every image is pinned to;
# - the pip packages of .github/python/requirements.txt.
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

    # @param versions [Array<String>] Versions, each optionally prefixed with `v`.
    # @return [String] The newest of them, as written.
    sig { params(versions: T::Array[String]).returns(String) }
    def self.newest(versions)
      versions.max_by { |text| version(text) }
        .to_s
    end

    # @param name [String] A PyPI package.
    # @return [String] Its newest release.
    sig { params(name: String).returns(String) }
    def self.pypi(name)
      Hash.try_convert(json("https://pypi.org/pypi/#{name}/json")).to_h.fetch('info').fetch('version').to_s
    end

    # The newest release tag of a GitHub repository and the commit it points to.
    #
    # @param repository [String] `owner/name` on GitHub.
    # @return [Array(String, String)] The tag and its commit.
    sig { params(repository: String).returns([String, String]) }
    def self.tag(repository)
      commits = tag_commits(repository)
      latest = newest(commits.keys)
      [latest, commits.fetch(latest)]
    end

    # The commit of every release tag of a GitHub repository: an annotated tag lists its commit
    # under `tag^{}` (after the tag object, so it wins), a lightweight tag only under `tag`.
    #
    # @param repository [String] `owner/name` on GitHub.
    # @return [Hash{String => String}] The commit of every release tag.
    sig { params(repository: String).returns(T::Hash[String, String]) }
    def self.tag_commits(repository)
      refs, status = Open3.capture2('git', 'ls-remote', '--tags', "https://github.com/#{repository}")
      abort("git ls-remote #{repository} failed") unless status.success?
      refs.lines.filter_map { |line| tag_entry(line) }
        .to_h
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

    # The digest a tag of a Docker Hub image points to now (an official image lives under
    # `library/`).
    #
    # @param repository [String] The image repository.
    # @param tag [String] The tag.
    # @return [String] The digest.
    sig { params(repository: String, tag: String).returns(String) }
    def self.digest(repository, tag)
      path = repository.include?('/') ? repository : "library/#{repository}"
      Hash.try_convert(json("#{DOCKER_HUB}/#{path}/tags/#{tag}")).to_h.fetch('digest').to_s
    end

    # @return [String] The newest Semgrep release published on Docker Hub.
    sig { returns(String) }
    def self.semgrep
      tags = JSON.parse(Net::HTTP.get(URI("#{DOCKER_HUB}/semgrep/semgrep/tags?page_size=100")).to_s)
      names = tags.fetch('results').map { |tag| tag.fetch('name').to_s }
      newest(names.grep(/\A\d+\.\d+\.\d+\z/))
    end
  end

  # What the repository itself pins and holds.
  module Local
    extend T::Sig

    # A Ruby version of a workflow: `ruby-version: 3.4.12`, or the expected version passed to
    # script/check_ruby.sh.
    RUBY_VERSION_PATTERN = /(?:ruby-version: |check_ruby\.sh )\K\d+\.\d+\.\d+\b/.freeze
    private_constant(:RUBY_VERSION_PATTERN)
    # A `ruby: [3.3.13, 3.4.12]` matrix (whose MRI entries are exact versions).
    RUBY_MATRIX_PATTERN = /^\s*ruby: \[([^\]]*)\]/.freeze
    private_constant(:RUBY_MATRIX_PATTERN)
    # The hold list.
    HOLDS = 'script/outdated_holds.yml'
    private_constant(:HOLDS)

    # @param path [String] A path relative to the repository root.
    # @return [String] The content of that file.
    sig { params(path: String).returns(String) }
    def self.read(path)
      File.read(File.join(ROOT, path))
    end

    # @return [Hash{String => String}] The text of every workflow, by file name.
    sig { returns(T::Hash[String, String]) }
    def self.workflows
      Dir[File.join(ROOT, '.github', 'workflows', '*.yml')].to_h { |path| [File.basename(path), File.read(path)] }
    end

    # @return [Hash{String => String}] The newest release of every held gem
    #   (script/outdated_holds.yml).
    sig { returns(T::Hash[String, String]) }
    def self.gem_holds
      gems = Hash.try_convert(YAML.safe_load(read(HOLDS))).to_h.fetch('gems')
      Hash.try_convert(gems).to_h.transform_values { |hold| hold.fetch('newest').to_s }
    end

    # @return [String] The Ruby mutation testing is held at (script/outdated_holds.yml).
    sig { returns(String) }
    def self.mutation_ruby_hold
      Hash.try_convert(YAML.safe_load(read(HOLDS))).to_h.fetch('mutation_ruby').to_s
    end

    # @return [Gem::Version] The Ruby of .ruby-version.
    sig { returns(Gem::Version) }
    def self.lockfile_ruby
      Upstream.version(read('.ruby-version').strip)
    end

    # @param text [String] A workflow.
    # @return [Array<String>] Every exact Ruby version it names.
    sig { params(text: String).returns(T::Array[String]) }
    def self.ruby_versions(text)
      matrix = text.scan(RUBY_MATRIX_PATTERN).flat_map { |list| list.to_s.split(', ') }
      versions = text.scan(RUBY_VERSION_PATTERN).map(&:to_s) + matrix.grep(/\A\d+\.\d+\.\d+\z/)
      versions.uniq
    end

    # @param gem [String] An installed gem.
    # @param path [String] A path inside it.
    # @return [String] The content of that file of the installed gem.
    sig { params(gem: String, path: String).returns(String) }
    def self.gem_file(gem, path)
      File.read(File.join(Gem.loaded_specs.fetch(gem).full_gem_path, path))
    end

    # @return [Array<Array(String, String)>] The name and version of every pip package
    #   .github/python/requirements.txt pins.
    sig { returns(T::Array[[String, String]]) }
    def self.pip_pins
      read('.github/python/requirements.txt').scan(/^([\w.-]+)==(\S+)/).map { |name, pinned| [name.to_s, pinned.to_s] }
    end
  end

  # The outdated gems of the bundle, as `bundle outdated --parseable` lists them.
  module Bundle
    extend T::Sig

    # One line of `bundle outdated --parseable`.
    OUTDATED_LINE = /\A(\S+) \(newest ([^,\s]+), installed ([^,)\s]+)/.freeze
    private_constant(:OUTDATED_LINE)
    # `bundle outdated` refuses to run in deployment mode, which `ruby/setup-ruby`'s bundler cache
    # turns on.
    ENV_OVERRIDES = T.let(
      { 'BUNDLE_DEPLOYMENT' => 'false', 'BUNDLE_FROZEN' => 'false' }.freeze, T::Hash[String, String]
    )
    private_constant(:ENV_OVERRIDES)

    # `bundle outdated` exits 1 when it reports an outdated gem, and with any other failure status
    # when it could not check at all.
    #
    # @return [Array<Array(String, String, String)>] Name, newest and installed version of every
    #   outdated gem.
    sig { returns(T::Array[[String, String, String]]) }
    def self.outdated
      output, status = Open3.capture2e(ENV_OVERRIDES, 'bundle', 'outdated', '--parseable', chdir: ROOT)
      abort("bundle outdated failed:\n#{output}") unless [0, 1].include?(status.exitstatus)
      output.lines.filter_map { |line| entry(line) }
    end

    # @param line [String] A line of `bundle outdated --parseable`.
    # @return [Array(String, String, String), nil] Name, newest and installed version; nil for any
    #   other line.
    sig { params(line: String).returns(T.nilable([String, String, String])) }
    def self.entry(line)
      match = OUTDATED_LINE.match(line)
      [match[1].to_s, match[2].to_s, match[3].to_s] if match
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

    # Records a problem unless what is pinned is the newest release.
    #
    # @param subject [String] What is pinned.
    # @param pinned [String] The pinned release.
    # @param newest [String] The newest release.
    # @return [void]
    sig { params(subject: String, pinned: String, newest: String).void }
    def compare(subject, pinned, newest)
      add("#{subject} #{pinned} is not the newest #{newest}") unless pinned == newest
    end

    # Prints how many problems were found.
    #
    # @return [Boolean] Whether no problem was found.
    sig { returns(T::Boolean) }
    def passed?
      count = @messages.size
      warn("#{count} problem(s)") if count.positive?
      count.zero?
    end
  end

  # The gems of the bundle against the gem holds.
  class Gems
    extend T::Sig

    sig { params(problems: Problems).void }
    def initialize(problems)
      @problems = problems
      @newest_by_gem = T.let(Local.gem_holds, T::Hash[String, String])
    end

    # Every outdated gem is held at its newest release, and every gem hold is still needed.
    #
    # @return [void]
    sig { void }
    def run
      outdated = Bundle.outdated
      outdated.each { |name, newest, installed| check(name, newest, installed) }
      (@newest_by_gem.keys - outdated.map(&:first)).each do |name|
        @problems.add("gem hold #{name} is stale: no longer outdated")
      end
    end

    private

    sig { params(name: String, newest: String, installed: String).void }
    def check(name, newest, installed)
      on_hold = @newest_by_gem[name] == newest
      puts("gem #{name} #{installed} -> #{newest}#{' (on hold)' if on_hold}")
      @problems.add("gem #{name} #{installed} -> #{newest} is not on the hold list") unless on_hold
    end
  end

  # The Rubies: .ruby-version, every exact CI Ruby and the mutation Ruby hold.
  class Rubies
    extend T::Sig

    sig { params(problems: Problems, workflows: T::Hash[String, String]).void }
    def initialize(problems, workflows)
      @problems = problems
      @workflows = workflows
      @mutation_ruby = T.let(Local.mutation_ruby_hold, String)
      @releases = T.let(Upstream.rubies, T::Array[Gem::Version])
    end

    # .ruby-version is the newest stable release, every exact CI Ruby the newest of its series,
    # and the mutation Ruby hold is still needed.
    #
    # @return [void]
    sig { void }
    def run
      @problems.compare('.ruby-version', Local.lockfile_ruby.to_s, @releases.max.to_s)
      @workflows.each { |name, text| check_workflow(name, text) }
      mutation_ruby
    end

    private

    sig { params(name: String, text: String).void }
    def check_workflow(name, text)
      Local.ruby_versions(text).each do |ruby|
        @problems.compare("#{name}: Ruby", ruby, newest_of_series(Upstream.version(ruby)).to_s)
      end
    end

    sig { params(ruby: Gem::Version).returns(T.nilable(Gem::Version)) }
    def newest_of_series(ruby)
      series = ruby.segments.first(2)
      @releases.select { |release| release.segments.first(2) == series }
        .max
    end

    # The mutation Ruby hold is still needed: mutant still loads parser/current, which still has
    # no grammar for the Ruby of .ruby-version; and the mutation workflow runs on the held Ruby.
    sig { void }
    def mutation_ruby
      series = Local.lockfile_ruby.segments.first(2).join('\\.')
      @problems.add('mutation Ruby hold is stale: mutant no longer requires parser/current') unless
        Local.gem_file('mutant', 'lib/mutant.rb').include?('parser/current')
      @problems.add('mutation Ruby hold is stale: parser/current has a grammar for .ruby-version') if
        Local.gem_file('parser', 'lib/parser/current.rb').include?("/^#{series}\\./")
      @problems.add("mutation.yml does not run on the held Ruby #{@mutation_ruby}") unless
        @workflows.fetch('mutation.yml').include?("ruby-version: #{@mutation_ruby}")
    end
  end

  # What a workflow pins: the Actions, the downloaded tools and the container images.
  class WorkflowPins
    extend T::Sig

    # The repositories of the tools the workflows download, by their `<NAME>_VERSION` variable.
    TOOLS = T.let(
      {
        'ACTIONLINT' => 'rhysd/actionlint',
        'EDITORCONFIG_CHECKER' => 'editorconfig-checker/editorconfig-checker',
        'GITLEAKS' => 'gitleaks/gitleaks',
        'LYCHEE' => 'lycheeverse/lychee',
        'SHELLCHECK' => 'koalaman/shellcheck',
        'SHFMT' => 'mvdan/sh',
        'TRIVY' => 'aquasecurity/trivy'
      }.freeze,
      T::Hash[String, String]
    )
    private_constant(:TOOLS)
    # `uses: owner/repo[/path]@<sha>  # <tag>`.
    ACTION_PIN = %r{uses: ([\w.-]+/[\w.-]+)[\w./-]*@(\h{40}) +# (\S+)}.freeze
    private_constant(:ACTION_PIN)
    # `<NAME>_VERSION: x.y.z`.
    TOOL_PIN = /\b(#{TOOLS.keys.join('|')})_VERSION: (\S+)/.freeze
    private_constant(:TOOL_PIN)
    # `<NAME>_IMAGE: repository:tag@sha256:...`.
    IMAGE_PIN = %r{_IMAGE: ([\w./-]+):([\w.-]+)@(sha256:\h+)}.freeze
    private_constant(:IMAGE_PIN)
    # The image whose tag must also be its newest release.
    SEMGREP = 'semgrep/semgrep'
    private_constant(:SEMGREP)

    sig { params(problems: Problems, workflow: String, text: String).void }
    def initialize(problems, workflow, text)
      @problems = problems
      @workflow = workflow
      @text = text
    end

    # Runs the checks on the workflow.
    #
    # @return [void]
    sig { void }
    def run
      actions
      tools
      images
    end

    private

    # Every GitHub Action is pinned to the commit of its newest release tag.
    sig { void }
    def actions
      @text.scan(ACTION_PIN).uniq.each do |repository, commit, tag|
        @problems.compare("#{@workflow}: #{repository}", "#{tag} #{commit}", Upstream.tag(repository.to_s).join(' '))
      end
    end

    # Every downloaded tool is at its newest release.
    sig { void }
    def tools
      @text.scan(TOOL_PIN).uniq.each do |tool, pinned|
        newest = Upstream.tag(TOOLS.fetch(tool.to_s)).first
        @problems.compare("#{@workflow}: #{tool}", pinned.to_s, Upstream.version(newest).to_s)
      end
    end

    # Every image is pinned to the digest its tag points to now.
    sig { void }
    def images
      @text.scan(IMAGE_PIN).uniq.each { |repository, tag, digest| image(repository.to_s, tag.to_s, digest.to_s) }
    end

    # An image is pinned to the digest its tag points to now; the Semgrep image is also its
    # newest release.
    sig { params(repository: String, tag: String, digest: String).void }
    def image(repository, tag, digest)
      subject = "#{@workflow}: image #{repository}:#{tag}"
      @problems.compare("#{subject} digest", digest, Upstream.digest(repository, tag))
      return unless repository == SEMGREP

      @problems.compare("#{subject} release", tag, Upstream.semgrep)
    end
  end

  # The pip packages of .github/python/requirements.txt are at their newest release.
  class PipPins
    extend T::Sig

    sig { params(problems: Problems).void }
    def initialize(problems)
      @problems = problems
    end

    # Runs the check.
    #
    # @return [void]
    sig { void }
    def run
      Local.pip_pins.each { |name, pinned| @problems.compare("pip package #{name}", pinned, Upstream.pypi(name)) }
    end
  end

  # Runs every check and reports whether all passed.
  #
  # @return [Boolean] Whether nothing is outdated.
  sig { returns(T::Boolean) }
  def self.passed?
    problems = Problems.new
    checks(problems).each(&:run)
    problems.passed?
  end

  # @param problems [Problems] Where every check records its problems.
  # @return [Array<Gems, Rubies, PipPins, WorkflowPins>] Every check, one per workflow for the pins.
  sig { params(problems: Problems).returns(T::Array[T.any(Gems, Rubies, PipPins, WorkflowPins)]) }
  def self.checks(problems)
    workflows = Local.workflows
    pins = workflows.map { |name, text| WorkflowPins.new(problems, name, text) }
    [Gems.new(problems), Rubies.new(problems, workflows), PipPins.new(problems), *pins]
  end
end

exit(Outdated.passed?)
