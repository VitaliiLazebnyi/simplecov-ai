# Contributing to simplecov-ai

Thanks for your interest in improving simplecov-ai! This document describes how to set up the
project locally and the checks your change is expected to pass.

## Getting started

```sh
git clone https://github.com/VitaliiLazebnyi/simplecov-ai.git
cd simplecov-ai
bundle install
```

The gem supports Ruby `>= 2.7` and SimpleCov `>= 0.18, < 2.0`. The CI matrix exercises Ruby
2.7, 3.2, 3.3, 3.4 and 4.0.

## Local checks

Every pull request must keep all of the following green — they are the same gates CI enforces:

```sh
bundle exec rspec                    # tests; the suite enforces 100% line + branch coverage
bundle exec rubocop                  # style / lint (zero offenses)
bundle exec srb tc --typed strong    # Sorbet type check
bundle exec yardoc --fail-on-warning # documentation builds cleanly
bundle exec yard stats --list-undoc  # must report 100.00% documented
gem build simplecov-ai.gemspec       # the gem packages successfully
```

## Guidelines

- **Coverage is enforced.** New code must be exercised by specs; the suite fails below 100% line
  and branch coverage. Coverage is measured for real, so make sure `spec/spec_helper.rb` still
  starts SimpleCov before the library is required.
- **Public API needs YARD docs.** Documentation coverage must stay at 100%.
- **Types.** Keep files `# typed: strict` and satisfy `srb tc --typed strong`. When adding a
  hand-written RBI for a dependency, verify it against the installed version.
- **Bypass directives** in test fixtures should be constructed so the repository directive
  auditor (`spec/quality/directive_auditor_spec.rb`) does not flag them — either place the
  directive inside a single source line (a string literal) or use the `format('# :noc%s:', 'ov')`
  placeholder pattern in heredocs.
- Update `CHANGELOG.md` under the unreleased/next version heading for any user-facing change.

## Reporting bugs

Open an issue with a minimal reproduction: the Ruby and SimpleCov versions, the configuration
used, and the coverage scenario (or a small fixture) that triggers the problem.
