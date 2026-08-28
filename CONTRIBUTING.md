# Contributing to simplecov-ai

Thanks for your interest in improving simplecov-ai! This document describes how to set up the
project locally and the checks your change is expected to pass.

## Getting started

```sh
git clone https://github.com/VitaliiLazebnyi/simplecov-ai.git
cd simplecov-ai
bin/setup          # bundle install
bundle exec rake   # every quality gate, see below
```

The gem supports Ruby `>= 2.7` and SimpleCov `>= 0.18, < 2.0`. CI exercises Ruby 2.7, 3.2, 3.3,
3.4 and 4.0 on Linux, plus non-blocking runs on Windows (Ruby 3.4), JRuby 9.4 and TruffleRuby.

## Local checks

`bundle exec rake` runs the same gates CI enforces, in this order; each one can also be run on
its own:

- `rake spec` — `RUBYOPT=-w bundle exec rspec`; the suite fails below 100% line, branch and (on
  MRI with SimpleCov >= 1.0) method coverage, and any Ruby warning emitted from `lib/` fails the
  run (`spec/support/warnings.rb`). Besides the unit specs it runs an end-to-end child-process
  spec through SimpleCov's real result-merging path (`spec/integration/`), a resolver run over the
  sources of every gem in the bundle (`spec/quality/resolver_corpus_spec.rb`;
  `RESOLVER_CORPUS_MAX_FILES=0` resolves all of them), a seeded property spec for the resolver
  (`RESOLVER_PROPERTY_SEED`) and a seeded resultset fuzz spec for the formatter
  (`FORMATTER_FUZZ_SEED`).
- `rake rubocop` — `bundle exec rubocop`; zero offenses, no `rubocop:disable` directives.
- `rake typecheck` — `bundle exec srb tc --typed strong`; every file is `# typed: strict`
  (skipped with a warning where sorbet-static has no build).
- `rake docs` — `bundle exec yardoc --fail-on-warning`, then `yard stats --list-undoc` must report
  100% documented.
- `rake audit` — `bundle exec bundler-audit check --update`; no known vulnerabilities in
  `Gemfile.lock`.
- `rake build` — `gem build simplecov-ai.gemspec --strict`, then the gem is installed into a
  clean `GEM_HOME` and required, so it must package, validate and load.

Two more tasks are available on demand:

- `rake quality` runs the advisory tools (reek with `.reek.yml`, flay, flog, debride). CI runs it
  in a non-blocking job; findings are worth reading but do not block a merge.
- `rake rbi` regenerates the Sorbet RBIs for dependencies (see *Type checking* below).
- `rake mutant` runs mutation testing with mutant (Ruby >= 3.3; configuration in `.mutant.yml`).
  CI runs it as a blocking gate and requires every mutation to be killed;
  `MUTANT_SINCE=<revision>` limits a local run to the subjects touched since that revision. Ignore
  patterns in `.mutant.yml` must carry a justification, and whole-report specs declare
  `mutant_expression: MutantScopes.spec_levels` (`spec/support/mutant_scopes.rb`) so that mutant
  treats each `describe '#name'` block as that method's specification.

CI additionally runs, all as blocking gates unless noted: actionlint and zizmor on the workflow
files, markdownlint (`npx markdownlint-cli2 "**/*.md"`, rules in `.markdownlint.yml`, ignores in
`.markdownlint-cli2.yaml`), typos (`_typos.toml`; locally `typos`, installable with
`brew install typos-cli` or `cargo install typos-cli`), Semgrep (`p/ruby`, `p/secrets`,
`p/security-audit`, `p/github-actions`), Gitleaks over the full history, mutation testing (`rake mutant`), CodeQL (Ruby and workflow
files), and — non-blocking — the OpenSSF Scorecard. The release workflow verifies that
`lib/simplecov-ai/version.rb` matches the tag, refuses to publish unless `CHANGELOG.md` has a
heading for the tagged version, re-runs the gates, and signs the gem only when `SIMPLECOV_AI_SIGN`
is set (the workflow sets it when the `GEM_PRIVATE_KEY` secret exists; the gemspec then verifies
the key matches `certs/`, and the workflow checks the built gem carries a certificate chain).

## Dependency policy

- `Gemfile.lock` **is committed** and resolved on Ruby 4.0. The single-version gates (lint,
  typecheck, docs, audit, build, release) always run against it, so a passing local `rake` means
  the same dependency set passes in CI. Update it deliberately with `bundle update` (or accept a
  Dependabot PR) and commit the result.
- The multi-Ruby test matrix deletes the lockfile before installing, because a set resolved on
  Ruby 4.0 cannot be installed on older Rubies (simplecov 1.x needs Ruby >= 3.2, sorbet and
  tapioca need >= 3.1). Each Ruby resolves its own dependencies, exactly as a user's bundle would.
- Runtime dependencies are declared in the gemspec; development dependencies that install
  everywhere are too. The Sorbet toolchain (`sorbet`, `tapioca`, `rubocop-sorbet`,
  `standard-sorbet`, `yard-sorbet`) and the advisory quality tools live in the `Gemfile` behind an
  MRI/non-Windows guard because `sorbet-static` ships no builds for Windows, JRuby or TruffleRuby.
- `gemfiles/simplecov_<line>.gemfile` pin each supported SimpleCov release line (0.18, 0.21, 0.22,
  1.0, 1.1); CI runs the suite against all of them on Ruby 3.4, and against 0.18 on Ruby 2.7
  (`BUNDLE_GEMFILE=gemfiles/simplecov_0.22.gemfile bundle exec rspec`).

## Verifying on other Rubies

`bin/check-ruby` runs the suite (or any command) on another Ruby inside its official Docker image,
resolving dependencies from scratch the way the CI matrix does. The checkout is streamed into the
container, so nothing in the container can touch your working tree:

```sh
bin/check-ruby 2.7                                          # bundle exec rspec on Ruby 2.7
bin/check-ruby 3.4 'bundle exec rspec spec/quality'         # explicit command
bin/check-ruby jruby:9.4                                    # any image reference works
BUNDLE_GEMFILE=gemfiles/simplecov_0.18.gemfile bin/check-ruby 2.7
```

`CHECK_RUBY_SETUP` runs inside the container before `bundle install`. The official `jruby` images
ship no C compiler, which prism (pulled in through rubocop-ast) needs, so use
`CHECK_RUBY_SETUP='apt-get update -qq && apt-get install -y -qq build-essential' bin/check-ruby jruby:9.4`
there (GitHub's runners already have one).

### Verifying on other engines

The JRuby, TruffleRuby and Windows jobs of CI are blocking, and each engine is one Rake task away
(the tasks wrap `bin/check-ruby` with the right image and setup; an optional last argument
replaces the command, and `BUNDLE_GEMFILE` is passed through):

```sh
rake check:jruby                                         # jruby:9.4, C compiler installed first
rake check:truffleruby                                   # ghcr.io/graalvm/truffleruby-community:latest
rake 'check:ruby[2.7]'                                   # any ruby:<version> image, or an image reference
rake 'check:ruby[3.4,bundle exec rspec spec/quality]'    # explicit command
```

JRuby and TruffleRuby record no branch or method coverage, and the suite passes there all the
same: it exercises the formatter's branch and method rendering with the hand-built SimpleCov data
of the unit specs (`spec/spec_helper.rb` lifts SimpleCov's engine gate for the examples, since
SimpleCov otherwise drops the branch and method statistics of a result on those engines), and
the end-to-end spec proves what a real run on such an engine produces: an `N/A` branch line and
line deficits only, as the README says. The suite's own 100% coverage mandate is MRI's gate:
both engines attribute some executed lines differently from MRI (JRuby the lines of a multi-line
`sig do … end` block, TruffleRuby every `case` line), so there coverage is measured and reported
in `coverage/ai_report.md` but not enforced. Windows is the one platform `bin/check-ruby` cannot
reach; what sets it apart — text-mode writes turning `\n` into `\r\n` — is exercised everywhere
by the suite's CRLF examples, and fixtures are written byte for byte.

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

Every Ruby file is `# typed: strict` and the gate runs `srb tc --typed strong`. Dependency RBIs
are generated by tapioca into `sorbet/rbi/gems/` (`rake rbi`, or `bin/tapioca gem`); only the
gems `lib/` calls into are generated, so add new development-only gems to the `exclude` list in
`sorbet/tapioca/config.yml`. Generated RBIs carry the `# typed: autogenerated` sigil (configured
via `typed_overrides`) because `--typed strong` would otherwise demand a signature on every
reflected gem method. Signatures for the handful of gem methods the library relies on live in the
hand-written overlays `sorbet/rbi/parser.rbi`, `sorbet/rbi/prism.rbi` and
`sorbet/rbi/simplecov.rbi`; keep their arity identical to the generated definitions, and leave
methods whose results the code narrows with `T.cast` untyped so those casts stay meaningful.
Re-run `rake rbi` after changing dependency versions and commit the regenerated files.

## Guidelines

- **Coverage is enforced.** New code must be exercised by specs; the suite fails below 100% line,
  branch and method coverage (method coverage on MRI with SimpleCov >= 1.0), and `rake mutant`
  must still kill every mutation — a line that is executed but whose behaviour no spec pins down
  is not covered. Coverage is measured for real, so make sure `spec/spec_helper.rb` still starts
  SimpleCov before the library is required.
- **Public API needs YARD docs.** Documentation coverage must stay at 100%.
- **Types.** Keep files `# typed: strict` and satisfy `srb tc --typed strong`. When adding a
  signature to a dependency overlay, verify it against the installed version.
- **Bypass directives.** The repository directive auditor (`spec/quality/directive_auditor_spec.rb`)
  fails on any line in `lib/` or `spec/` that starts with `# :nocov:` or `# rubocop:disable`
  unless the line above it is a `# Justification:` (or `# Reason:`) comment. Specs that need a
  real `# :nocov:` marker in a fixture source should take it from the `nocov_marker` helper in
  `spec/support/simplecov_fixtures.rb`, which assembles the text from fragments so no such line
  appears in the spec file itself.
- **Fixtures with asserted line numbers.** `spec/fixtures/resolver_constructs.rb` is parsed, not
  loaded, and `ast_resolver_spec.rb` asserts the exact node table (names and line ranges) derived
  from it, so append new constructs at the end rather than inserting them.
- Update `CHANGELOG.md` under the `[Unreleased]` heading for any user-facing change; the release
  workflow refuses to publish a version that has no changelog heading.

## Reporting bugs

Open an issue with a minimal reproduction: the Ruby and SimpleCov versions, the configuration
used, and the coverage scenario (or a small fixture) that triggers the problem.
