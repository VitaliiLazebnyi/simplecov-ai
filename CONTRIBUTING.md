# Contributing to `simplecov-ai`

Thanks for your interest in improving `simplecov-ai`! This document describes how to set up the
project locally and the gates your change has to pass. Every gate below is enforced in CI and
fails the build; none of them has an exception list.

## Getting started

```sh
git clone https://github.com/VitaliiLazebnyi/simplecov-ai.git
cd simplecov-ai
bin/setup                              # bundle install
git config core.hooksPath .githooks    # optional: run the fast gates before every commit
script/check                           # every gate CI runs, see below
```

The gem supports Ruby `>= 2.7` and SimpleCov `>= 0.18, < 2.0`. Development happens on the Ruby
in `.ruby-version` (the newest Ruby release); the development tooling installs on MRI >= 3.3 on
Linux and macOS only (see the `Gemfile`), while every other Ruby, engine and platform installs
the test bundle (`gemfiles/test.gemfile`).

## The gates

`script/check` runs every check CI runs, then fails on any warning in their output exactly as the
CI warning gate does; `script/check --fast` leaves out the Docker runs (the Ruby matrix and
mutation testing). Every Ruby command runs with all warnings on: `-w -W:deprecated
-W:performance` (`script/rubyopt.rb`; the performance category exists on MRI >= 3.3 only).
`script/upstream_warnings.rb` drops a short, version-pinned list of warnings that the newest
releases of YARD, kramdown, Tapioca, bundler-audit and SimpleCov emit about their own code;
every other warning fails.

`bundle exec rake` runs the Ruby gates, in order:

- `rake spec`: RSpec; 100% line, branch and (SimpleCov >= 1.0) method coverage on MRI; no pending,
  skipped or focused example; any warning that reaches STDERR, from `lib/`, `spec/` or a
  dependency, fails the run (`spec/support/warnings.rb`).
- `rake rubocop`: RuboCop with every cop of RuboCop and of its plugins (`rubocop-md`,
  `-packaging`, `-performance`, `-rake`, `-rspec`, `-sorbet`, `-thread_safety` and `-yard`)
  enabled (`EnabledByDefault`); the few cops that are off are listed in `.rubocop.yml`, each with
  the cop or contract it contradicts. No todo file, no inline directives.
- `rake suppressions`: no inline suppression anywhere (`script/forbidden_suppressions.sh`, see
  *Rules*).
- `rake typecheck`: Tapioca generates the gem RBIs, then `srb tc` must report no errors over the
  whole repository, `spec/` included; every `lib/` file is `# typed: strong` except
  `branch_enricher.rb` (`strict`, see its header), and every other file is at least `strict`
  (`spec_helper.rb` and `spec/support/` included), except the example files and the fixtures of
  `spec/` (`typed: false`, the reason is in `.rubocop.yml`).
- `rake yard`: YARD builds without warnings and reports 100% documented.
- `rake reek`: no code smell (Reek's default configuration; `.reek.yml` narrows one detector for
  one class, with the reason).
- `rake flay`, `rake flog`, `rake debride`: no structural duplication (Flay mass 20; below it
  Flay only reports the identical Sorbet signatures of sibling methods), no method scoring above
  20 (the end of Flog's "good" band), no method without a caller (the few callers debride cannot
  see are listed in the `Rakefile`).
- Reek, Flay, Flog and debride check every Ruby source of the gem and its tooling: `lib/`,
  `script/`, the `Rakefile`, the gemspec and the Gemfiles (`CODE_SOURCES` in the `Rakefile`). The
  specs are held to RuboCop with `rubocop-rspec` instead.
- `rake audit`: bundler-audit, no locked gem with a known vulnerability.
- `rake build`: `gem build --strict`, then the gem is installed into a clean `GEM_HOME` and
  required with `ruby -w`.

Also enforced on every pull request and every push to `main`:

- **Mutation testing** (`bundle exec rake mutant`, `.mutant.yml`) covers every method under
  `SimpleCov::Formatter::AIFormatter` with no ignore patterns, and every mutation must be killed.
  CI runs it on Ruby 3.3.13 (`script/check` in the `ruby:3.3.13` image): mutant requires
  `parser/current`, and the newest `parser` gem only has a grammar for Ruby 3.3 and warns on any
  other Ruby (the hold is documented in `script/outdated_holds.yml` and `rake outdated` fails once
  it is no longer needed). While iterating, run one scope at a time, e.g.
  `bundle exec mutant run 'SimpleCov::Formatter::AIFormatter::LineSpan*'`. A surviving mutant
  needs a test that kills it, or, when the mutation cannot change observable behaviour, simpler
  code.
- **Dependency freshness** (`bundle exec rake outdated`, `script/outdated.rb`): `bundle outdated`,
  `.ruby-version` against the newest Ruby release, every exact Ruby in the workflows against the
  newest release of its series, every Action against the commit of its newest release tag, the
  downloaded tools and the Semgrep image against their newest releases, every container image
  against the digest its tag points to and the pip packages (`.github/python/requirements.txt`).
  The only exceptions are the holds in
  `script/outdated_holds.yml`, each with the upstream constraint that blocks it. Dependabot
  proposes updates for every ecosystem (`.github/dependabot.yml`).
- **Test matrix**: MRI 2.7, 3.2, 3.3, 3.4 and 4.0 (newest patch release each, each resolving its
  own test bundle; Ruby 2.7 in its official Docker image, as `ruby/setup-ruby` has no 2.7 build
  for the current runner image), the lockfile bundle, Windows, JRuby and TruffleRuby, and every
  SimpleCov line from 0.18 to 1.3 (`gemfiles/`).
- **Every other file type**: rumdl with every markdownlint rule and rumdl's own, the optional ones
  included (`.rumdl.toml`), yamllint in strict mode with every rule but key-ordering
  (`.yamllint.yml`), ShellCheck with every optional check at the style level (`.shellcheckrc`)
  and shfmt on every shell script (`script/shell_scripts.sh`), actionlint (with ShellCheck on
  every `run:` script), zizmor (auditor persona, with its online audits) on the workflows and
  `dependabot.yml`, editorconfig-checker (`.editorconfig`), lychee on every link and anchor of
  the Markdown files (`lychee.toml`), typos (`_typos.toml`).
- **Security**: Semgrep (`p/ruby`, `p/secrets`, `p/security-audit`, `p/github-actions`), gitleaks
  over the full history, Trivy (a known vulnerability of any severity in `Gemfile.lock` or
  `.github/python/requirements.txt`, and secrets in the working tree), bundler-audit, the
  dependency review (fails on a vulnerability of any severity), the OpenSSF Scorecard of every
  dependency (`bundle exec rake scorecard`: every gem, Action and pip package at or above 3, or
  allowed with its reason in `script/scorecard_allowlist.yml`), CodeQL (Ruby and the workflows)
  and the repository's own OpenSSF Scorecard.
- **Hardened runners**: every job starts with Harden-Runner, without telemetry, and may only
  reach the endpoints listed with it (audit mode on Windows, the only mode it supports there);
  sudo is removed from every Linux job, and so is Docker where the job does not run a container.
  Every Action is pinned to a commit, every downloaded tool and Python package to its SHA-256,
  and every container image to its digest. Every release is signed: the release fails without
  the signing key.
- **Warning gate**: every workflow ends with a job (`script/warning_gate.sh`) that fails the run
  when the log of any other job contains a warning or a deprecation notice.

`script/check` expects `actionlint`, `docker`, `editorconfig-checker`, `gh` (signed in: zizmor's
online audits use its token), `gitleaks`, `lychee`, `python3`, `shellcheck`, `shfmt`, `trivy`
and `typos` on the `PATH` (rumdl, yamllint and zizmor are installed from the hash-pinned
`.github/python/requirements.txt`). CI alone runs CodeQL, the repository's own Scorecard, the
dependency review (GitHub services) and the Windows job.

## Rules

- **No inline suppressions.** Nothing may silence a linter, scanner, type checker, coverage
  tool, warning or test in place: no `rubocop:disable`, `:reek:`, `nosemgrep`, `zizmor: ignore`,
  `shellcheck disable`, `yamllint disable`, `rumdl-disable`, `markdownlint-disable`, `gitleaks:allow`,
  `mutant:disable`, nocov or `simplecov:disable`
  directives in `lib/`, `T.unsafe` / `T.cast` / `T.bind` / `T.must` / `T.untyped` in the Ruby
  sources of the gem and its tooling,
  `$VERBOSE = nil`, `skip` / `pending` / focused examples, `continue-on-error`, and so on
  (`script/forbidden_suppressions.sh` has the full list). Fix the cause. A rule that genuinely
  cannot apply to a file is configured narrowly in the tool's configuration file, with the reason
  next to it.
- **No warnings.** Not from the gem, not from the specs, not from a dependency, not in a CI log.
  An example that feeds SimpleCov a deliberately deprecated input asserts the resulting notice
  (see `write_source` in `spec/support/simplecov_fixtures.rb`) instead of letting it through.
- **No skipped tests.** An example asserting a capability a platform lacks (method coverage on
  SimpleCov < 1.0, branch coverage on JRuby) is not defined there; every other example asserts
  what happens on every platform.
- **Behaviour is specified.** Every behavioural fix needs a regression spec, and every surviving
  mutant needs a test that kills it.
- **Types.** Keep `lib/` at `typed: strong`. Gem methods `lib/` calls are typed in the overlays
  `sorbet/rbi/parser.rbi`, `prism.rbi`, `simplecov.rbi` and `rubygems.rbi` (keep their arity identical to the
  generated definitions); type-checker-only declarations live in `sorbet/rbi/shims.rbi`.
- **Public API needs YARD docs.** Documentation coverage must stay at 100%.
- **Fixtures with asserted line numbers.** `spec/fixtures/resolver_constructs.rb` is parsed, not
  loaded, and `ast_resolver_spec.rb` asserts the exact node table derived from it, so append new
  constructs at the end rather than inserting them.
- Update `CHANGELOG.md` under the `[Unreleased]` heading for any user-facing change; the release
  workflow refuses to publish a version that has no changelog heading.

## Dependency policy

- `Gemfile.lock` **is committed** and resolved on the Ruby in `.ruby-version`; the single-version
  gates and the release run against it. Update it with `bundle update` and commit the result;
  `rake outdated` then tells whether anything is still behind.
- The test matrix deletes the lockfile before installing, because a set resolved on the newest
  Ruby cannot be installed on older Rubies; each Ruby resolves its own test bundle, exactly as a
  user's bundle would.
- `gemfiles/simplecov_<line>.gemfile` pin each supported SimpleCov release line
  (`BUNDLE_GEMFILE=gemfiles/simplecov_0.22.gemfile bundle exec rspec`).

## Verifying on other Ruby versions and engines

`bin/check-ruby` runs the suite (or any command) on another Ruby inside its official Docker image,
resolving dependencies from scratch the way the CI matrix does. The checkout is streamed into the
container, so nothing in the container can touch your working tree:

```sh
bin/check-ruby 2.7                                          # bundle exec rspec on Ruby 2.7
bin/check-ruby 3.4 'bundle exec rspec spec/quality'         # explicit command
BUNDLE_GEMFILE=gemfiles/simplecov_0.18.gemfile bin/check-ruby 2.7
rake check:jruby                                            # JRuby, C compiler installed first
rake check:truffleruby                                      # TruffleRuby
```

JRuby and TruffleRuby record no branch or method coverage; the suite exercises the formatter's
branch and method rendering with hand-built SimpleCov data there (`spec/spec_helper.rb` lifts
SimpleCov's engine gate for the examples), and the end-to-end spec proves what a real run on
such an engine produces. The 100% coverage mandate is MRI's gate: both engines attribute some
executed lines differently from MRI.

## Trying it on a sample project

The suite drives the formatter with real SimpleCov objects, but reading a digest produced by a
real test run is the quickest way to judge a change to the report. Create a throwaway project
with a `Gemfile` that points at your checkout (`gem 'simplecov-ai', path: '/path/to/checkout'`),
a `spec_helper.rb` that starts SimpleCov with `enable_coverage :branch` (and
`enable_coverage :method` on SimpleCov >= 1.0) and registers `SimpleCov::Formatter::AIFormatter`,
plus a spec that leaves some code unexecuted; `bundle exec rspec` then prints
`AI coverage digest written to …/coverage/ai_report.md`. To run the same project on another Ruby
or SimpleCov, keep it inside the checkout — in a directory `bin/check-ruby` streams, so not
`tmp/`, `coverage/` or `vendor/` — with `gem 'simplecov-ai', path: '..'` in its `Gemfile`, and
pass the command through (do not commit the sample):

```sh
bin/check-ruby 3.4 'cd e2e && bundle install --quiet && bundle exec rspec; cat coverage/ai_report.md'
```

## Reporting bugs

Open an issue with a minimal reproduction: the Ruby and SimpleCov versions, the configuration
used, and the coverage scenario (or a small fixture) that triggers the problem.
