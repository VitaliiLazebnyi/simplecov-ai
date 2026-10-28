#!/usr/bin/env ruby
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
# - the tools the workflows download (actionlint, gitleaks) and the Semgrep image.
module Outdated
  ROOT = T.let(File.expand_path('..', __dir__), String)

  # Newest releases, as published upstream.
  module Upstream
    extend T::Sig

    # Release tags of the form `1.2.3` or `v1.2.3`, optionally peeled (`^{}`).
    RELEASE_TAG = %r{\Arefs/tags/(v?\d+\.\d+\.\d+)(\^\{\})?\z}.freeze

    sig { params(text: String).returns(Gem::Version) }
    def self.version(text)
      Gem::Version.new(text.delete_prefix('v'))
    end

    # The newest release tag of a GitHub repository and the commit it points to: an annotated
    # tag lists its commit under `tag^{}` (after the tag object, so it wins), a lightweight tag
    # only under `tag`.
    sig { params(repository: String).returns([String, String]) }
    def self.tag(repository)
      refs, status = Open3.capture2('git', 'ls-remote', '--tags', "https://github.com/#{repository}")
      abort "git ls-remote #{repository} failed" unless status.success?
      tags = refs.lines.filter_map { |line| tag_entry(line) }
      newest = tags.map(&:first).max_by { |tag| version(tag) }.to_s
      [newest, tags.to_h.fetch(newest)]
    end

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
      index.scan(/^ruby-(\d+\.\d+\.\d+)\s/).flatten.map { |release| version(release) }
    end

    sig { returns(String) }
    def self.semgrep
      tags = JSON.parse(Net::HTTP.get(URI('https://hub.docker.com/v2/repositories/semgrep/semgrep/tags?page_size=100')).to_s)
      names = tags.fetch('results').map { |tag| tag.fetch('name') }.grep(/\A\d+\.\d+\.\d+\z/)
      names.max_by { |name| version(name) }.to_s
    end
  end

  # The gem holds of the hold list against `bundle outdated`.
  class GemHolds
    extend T::Sig

    # One line of `bundle outdated --parseable`.
    OUTDATED_LINE = /\A(\S+) \(newest ([^,\s]+), installed ([^,)\s]+)/.freeze

    # @return [Array<Array(String, String, String)>] Name, newest and installed version of every
    #   outdated gem.
    sig { returns(T::Array[[String, String, String]]) }
    def self.outdated
      output, = Open3.capture2e('bundle', 'outdated', '--parseable', chdir: ROOT)
      output.lines.filter_map do |line|
        match = OUTDATED_LINE.match(line)
        [match[1].to_s, match[2].to_s, match[3].to_s] if match
      end
    end

    sig { params(holds: BasicObject).void }
    def initialize(holds)
      @newest_by_gem = T.let(Hash.try_convert(holds).to_h.transform_values { |hold| hold.fetch('newest').to_s },
                             T::Hash[String, String])
    end

    # @return [String, nil] The problem with an outdated gem, nil when it is held at that release.
    sig { params(name: String, newest: String, installed: String).returns(T.nilable(String)) }
    def problem(name, newest, installed)
      on_hold = @newest_by_gem[name] == newest
      puts "gem #{name} #{installed} -> #{newest}#{' (on hold)' if on_hold}"
      "gem #{name} #{installed} -> #{newest} is not on the hold list" unless on_hold
    end

    # @return [Array<String>] The held gems that are no longer outdated.
    sig { params(outdated: T::Array[String]).returns(T::Array[String]) }
    def stale(outdated)
      @newest_by_gem.keys - outdated
    end
  end

  # The checks, collecting every problem before failing.
  class Check
    extend T::Sig

    # The repositories of the tools the workflows download, by their `<NAME>_VERSION` variable.
    TOOLS = T.let({ 'ACTIONLINT' => 'rhysd/actionlint', 'GITLEAKS' => 'gitleaks/gitleaks' }.freeze,
                  T::Hash[String, String])

    sig { void }
    def initialize
      @holds = T.let(YAML.safe_load_file(File.join(ROOT, 'script', 'outdated_holds.yml')), T::Hash[String, BasicObject])
      @workflows = T.let(Dir[File.join(ROOT, '.github', 'workflows', '*.yml')].to_h do |path|
        [File.basename(path), File.read(path)]
      end, T::Hash[String, String])
      @problems = T.let([], T::Array[String])
    end

    sig { returns(T::Boolean) }
    def passed?
      gems
      rubies
      mutation_ruby
      actions
      tools
      return true if @problems.empty?

      warn "#{@problems.size} problem(s)"
      false
    end

    private

    sig { params(message: String).void }
    def problem(message)
      @problems << message
      warn "OUTDATED: #{message}"
    end

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
        gem_holds.problem(name, newest, installed)&.then do |text|
          problem(text)
        end
      end
      gem_holds.stale(outdated.map(&:first)).each { |name| problem("gem hold #{name} is stale: no longer outdated") }
    end

    # Ruby: .ruby-version is the newest stable release, every exact CI Ruby the newest of its series.
    sig { void }
    def rubies
      releases = Upstream.rubies
      problem(".ruby-version #{lockfile_ruby} is not the newest Ruby #{releases.max}") if lockfile_ruby != releases.max
      @workflows.each do |name, text|
        text.scan(/"(\d+\.\d+\.\d+)"/).flatten.uniq.each { |ruby| newest_of_series(name, ruby.to_s, releases) }
      end
    end

    sig { params(name: String, ruby: String, releases: T::Array[Gem::Version]).void }
    def newest_of_series(name, ruby, releases)
      series = Upstream.version(ruby).segments.first(2)
      newest = releases.select { |release| release.segments.first(2) == series }.max
      problem("#{name}: Ruby #{ruby} is not the newest of its series, #{newest}") if Upstream.version(ruby) != newest
    end

    # The mutation Ruby hold is still needed: mutant still loads parser/current, which still has
    # no grammar for the Ruby of .ruby-version; and the mutation workflow runs on the held Ruby.
    sig { void }
    def mutation_ruby
      series = lockfile_ruby.segments.first(2).join('\\.')
      problem('mutation Ruby hold is stale: mutant no longer requires parser/current') unless
        gem_file('mutant', 'lib/mutant.rb').include?('parser/current')
      problem('mutation Ruby hold is stale: parser/current has a grammar for .ruby-version') if
        gem_file('parser', 'lib/parser/current.rb').include?("/^#{series}\\./")
      hold = @holds.fetch('mutation_ruby')
      problem("mutation.yml does not run on the held Ruby #{hold}") unless
        @workflows.fetch('mutation.yml').include?(%(ruby-version: "#{hold}"))
    end

    sig { params(gem: String, path: String).returns(String) }
    def gem_file(gem, path)
      File.read(File.join(Gem.loaded_specs.fetch(gem).full_gem_path, path))
    end

    # GitHub Actions: `uses: owner/repo[/path]@<sha> # <tag>` names the newest tag, pinned to its commit.
    sig { void }
    def actions
      @workflows.each do |name, text|
        text.scan(%r{uses: ([\w.-]+/[\w.-]+)[\w./-]*@(\h{40}) # (\S+)}).uniq.each do |repository, commit, tag|
          newest = Upstream.tag(repository.to_s)
          problem("#{name}: #{repository} #{tag} (#{commit}) is not #{newest.join(' ')}") if [tag, commit] != newest
        end
      end
    end

    sig { params(name: String, tool: String, pinned: String).void }
    def tool(name, tool, pinned)
      newest, = Upstream.tag(TOOLS.fetch(tool))
      problem("#{name}: #{tool} #{pinned} is not the newest #{newest}") if "v#{pinned}" != newest
    end

    # Downloaded tools (`<NAME>_VERSION: x.y.z`) and the Semgrep image are at their newest release.
    sig { void }
    def tools
      @workflows.each do |name, text|
        text.scan(/(ACTIONLINT|GITLEAKS)_VERSION: (\S+)/).uniq.each do |tool, pinned|
          tool(name, tool.to_s, pinned.to_s)
        end
        text.scan(%r{image: semgrep/semgrep:(\S+)@}).flatten.uniq.each do |pinned|
          newest = Upstream.semgrep
          problem("#{name}: semgrep image #{pinned} is not the newest #{newest}") if pinned != newest
        end
      end
    end
  end
end

exit(Outdated::Check.new.passed?)
