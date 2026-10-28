# Contributing to simplecov-ai

Thanks for your interest in improving simplecov-ai! This document describes how to set up the
project locally and the gates your change has to pass. Every gate below is enforced in CI and
fails the build; none of them has an exception list.

## Getting started

```sh
git clone https://github.com/VitaliiLazebnyi/simplecov-ai.git
cd simplecov-ai
bin/setup                              # bundle install
git config core.hooksPath .githooks    # optional: run the fast gates before every commit
bundle exec rake                       # every local gate, see below
```

The gem supports Ruby `>= 2.7` and SimpleCov `>= 0.18, < 2.0`. Development happens on the Ruby
in `.ruby-version` (the newest Ruby release); the development tooling installs on MRI >= 3.3 on
Linux and macOS only (see the `Gemfile`), while every other Ruby, engine and platform installs
the test bundle declared in the gemspec.

## The gates

`bundle exec rake` runs, in order:

| Task | Gate |
| --- | --- |
| `rake spec` | RSpec with `ruby -w`; 100% line, branch and (SimpleCov >= 1.0) method coverage on MRI; no pending, skipped or focused example; any warning that reaches STDERR — from `lib/`, `spec/` or a dependency — fails the run (`spec/support/warnings.rb`) |
| `rake rubocop` | RuboCop with rubocop-md, -packaging, -performance, -rake, -rspec, -sorbet and -thread_safety (`.rubocop.yml`); no todo file, no inline directives |
| `rake suppressions` | no inline suppression anywhere (`script/forbidden_suppressions.sh`, see *Rules*) |
| `rake typecheck` | Tapioca generates the gem RBIs, then `srb tc` must report no errors; every `lib/` file is `# typed: strong` except `branch_enricher.rb` (`strict`, see its header) |
| `rake yard` | YARD builds without warnings and reports 100% documented |
| `rake reek` | no code smell (Reek's default configuration; `.reek.yml` narrows one detector for one class, with the reason) |
| `rake flay` / `rake flog` / `rake debride` | no structural duplication, no method above the flog threshold, no method without a caller (the few callers debride cannot see are listed in the `Rakefile`) |
| `rake audit` | bundler-audit: no locked gem with a known vulnerability |
| `rake build` | `gem build --strict`, then the gem is installed into a clean `GEM_HOME` and required with `ruby -w` |

Also enforced in CI, outside the default task:

```sh
bundle exec rake mutant     # mutation testing: every mutation of every subject must be killed
bundle exec rake outdated   # every gem, Ruby, Action and tool at its newest release, or on the hold list
```

- **Mutation testing** (`.mutant.yml`) covers every method under `SimpleCov::Formatter::AIFormatter`
  with no ignore patterns. CI runs it on Ruby 3.3.13: mutant requires `parser/current`, and the
  newest `parser` gem only has a grammar for Ruby 3.3 and warns on any other Ruby (the hold is
  documented in `script/outdated_holds.yml` and `rake outdated` fails once it is no longer
  needed). Locally it runs on any Ruby >= 3.3 (on others than 3.3.13 with that one warning);
  while iterating, run one scope at a time, e.g.
  `bundle exec mutant run 'SimpleCov::Formatter::AIFormatter::LineSpan*'`. A surviving mutant
  needs a test that kills it, or — when the mutation cannot change observable behaviour —
  simpler code.
- **Dependency freshness** (`script/outdated.rb`): `bundle outdated`, `.ruby-version` against the
  newest Ruby release, every exact Ruby in the workflows against the newest release of its series,
  every Action against the commit of its newest release tag, and the downloaded tools and the
  Semgrep image against their newest releases, and every container image against the digest its
  tag points to. The only exceptions are the holds in
  `script/outdated_holds.yml`, each with the upstream constraint that blocks it.
- **Test matrix**: MRI 2.7, 3.2, 3.3, 3.4 and 4.0 (newest patch release each, each resolving its
  own test bundle; Ruby 2.7 in its official Docker image, as `ruby/setup-ruby` has no 2.7 build
  for the current runner image), the lockfile bundle, Windows, JRuby and TruffleRuby, and every
  SimpleCov line from 0.18 to 1.3 (`gemfiles/`).
- **Linters and scanners**: actionlint (with ShellCheck on every `run:` script), ShellCheck on
  `script/`, `bin/` and the hook, zizmor (pedantic), markdownlint (`.markdownlint.yml`), typos
  (`_typos.toml`), Semgrep (`p/ruby`, `p/secrets`, `p/security-audit`, `p/github-actions`),
  gitleaks over the full history, bundler-audit, the dependency review, CodeQL and the OpenSSF
  Scorecard.
- **Warning gate**: every workflow ends with a job (`script/warning_gate.sh`) that fails the run
  when the log of any other job contains a warning or a deprecation notice.

Locally, `actionlint`, `shellcheck`, `zizmor --offline --persona pedantic .github/workflows`,
`typos`, `npx markdownlint-cli2 "**/*.md"` and `gitleaks git .` run the same checks.

## Rules

- **No inline suppressions.** Nothing may silence a linter, scanner, type checker, coverage
  tool, warning or test in place: no `rubocop:disable`, `:reek:`, `nosemgrep`, `zizmor: ignore`,
  `shellcheck disable`, `gitleaks:allow`, `mutant:disable`, nocov or `simplecov:disable`
  directives in `lib/`, `T.unsafe` / `T.cast` / `T.bind` / `T.must` / `T.untyped` in `lib/`,
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

## Verifying on other Rubies and engines

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

## Type checking

## Reporting bugs

Open an issue with a minimal reproduction: the Ruby and SimpleCov versions, the configuration
used, and the coverage scenario (or a small fixture) that triggers the problem.
