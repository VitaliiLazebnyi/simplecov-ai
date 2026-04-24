# Ruby Gem Development Practices & Configuration Guide

This document captures the best practices, architectural approaches, and configurations utilized in modern, high-quality Ruby gems (such as `http_loader`). It serves as a blueprint for AI agents and developers building resilient, well-tested, securely-released, and strictly-typed Ruby gems.

## 1. Static Type Checking with Sorbet

The project leverages [Sorbet](https://sorbet.org/) for robust, static type checking.

- **Dependencies**: Includes `sorbet-runtime` as a runtime dependency and `sorbet` / `yard-sorbet` as development dependencies.
- **Static Configuration**: The `sorbet/config` file is used to aggressively ignore irrelevant paths (`vendor/`, `coverage/`, `doc/`, `spec/`, etc.) to improve scanning performance.
- **Strictness**: Code files are expected to utilize `# typed: strong` or `# typed: strict` inline pragmas to ensure comprehensive type safety.
- **Runtime Testing Exclusions**: Within `spec/spec_helper.rb`, the runtime type error listeners are stubbed out during RSpec execution:
  ```ruby
require 'sorbet-runtime'
T::Configuration.inline_type_error_handler = ->(_, _) {}
T::Configuration.call_validation_error_handler = ->(_, _) {}
  ```
  This guarantees that negative tests asserting behavior with invalid attributes don't crash from Sorbet runtime validations.

## 2. Code Quality & Linting (RuboCop)

The codebase implements strict coding standards through RuboCop, leveraging several specialized plugins beyond the default rule set.

- **Applied Plugins**:
  - `rubocop-performance`
  - `rubocop-thread_safety` (imperative for async/threaded workloads)
  - `rubocop-rake`, `rubocop-rspec`, `rubocop-md` (Markdown linting).
- **Custom Local Cops**: The configuration allows for custom, domain-specific AI cops defined in the project:
  ```yaml
  require:
    - ./lib/rubocop/cop/ai/adverb_spam.rb
  AI/AdverbSpam:
    Enabled: true
  ```
- **Custom Plugin Configuration Injection**: When a RuboCop extension must programmatically enforce a core layer of configurable defaults, inject it safely using `RuboCop::ConfigLoader`. Remember that merging two `RuboCop::Config` instances natively strips the enclosing class and evaluates to a primitive `Hash`, which crashes subsequent RuboCop initializations (e.g., `undefined method 'for_all_cops' for an instance of Hash`). Always explicitly re-wrap the response:
  ```ruby
path = File.join(RuboCop::AI.project_root, 'config', 'default.yml')
hash = T.cast(RuboCop::ConfigLoader.send(:load_yaml_configuration, path), T::Hash[T.untyped, T.untyped])
config = RuboCop::Config.new(hash, path)
config.make_excludes_absolute

merged = RuboCop::ConfigLoader.default_configuration.merge(config)
merged_config = RuboCop::Config.new(merged.to_h, RuboCop::ConfigLoader.default_configuration.loaded_path)
RuboCop::ConfigLoader.instance_variable_set(:@default_configuration, merged_config)
  ```
- **Constraints enforced**:
  - `Style/FrozenStringLiteralComment: Enabled: true` (for memory footprint optimization).
  - Target Ruby execution contexts are explicitly defined.
  - **No Inline Exceptions**: The codebase strictly forbids the use of inline RuboCop disable directives (e.g., `# rubocop:disable All`). RuboCop offenses must be actively resolved via architectural refactoring rather than silenced.
  - **Minimal Configuration Exceptions**: Usage of exceptions within `.rubocop.yml` must be strictly minimized. Exceptions should only be added if they are absolutely inevitable (e.g., overriding `Naming/FileName` for gem entry files). For rule adjustments, utilize supported configuration parameters (e.g., `EnforcedStyle: gemspec` for `Gemspec/DevelopmentDependencies`) rather than silencing cops.

## 3. RSpec Testing Suite

1. **RSpec Configuration** (`.rspec`):
   - Execution is randomized (`--order random`) to expose state bleed between tests.
   - Profiling is enabled (`--profile 10`) to identify the top 10 slowest executing tests continuously.
2. **Coverage mandates (SimpleCov)**:
   - Initialized in `spec_helper.rb`, setting `enable_coverage :branch` mapping all tested code.
   - **Strict 100% Coverage**: 100% logic and branch test coverage is rigorously mandated.
   - **No Exemptions**: The codebase strictly forbids the use of coverage-dodging exception directives (e.g., `# rubocop:disable`, `# type: ignore`, `# pragma: no cover`) to artificially inflate coverage metrics. All tests must verify real state changes.
3. **Mocks and Expectations**:
   - `verify_partial_doubles = true` ensures that when mocking an object, it accurately implements the original object's signature preventing "mock drift".
4. **Anti-Coverage Paradox Protocol**:
   - **Strict Mock Fidelity**: Test doubles and exceptions must mathematically align with real runtime constraints (e.g., preventing silent deviations or mocking generic exceptions when a dependency natively throws a specialized one).
   - **Structural Boundary Testing**: Algorithm assertions must evaluate using deep, nested context hierarchies (like complex AST trees) to validate real-world boundary conditions, rather than simple, flat arrays.
   - **Ordered Output Assertions**: Text output testing MUST use multi-line Regex to enforce sequential structuring and chronological order. Strictly ban isolated string presence assertions (`.to include()`) on formatted output.

## 4. Documentation (YARD)

YARD heavily drives code discoverability and API usability.

- **Configuration** (`.yardopts`):
  - Configures the output format as markdown (`--markup markdown`).
  - Instructs YARD to utilize the `sorbet` plugin (`--plugin sorbet`) so Sorbet signatures are automatically ingested into documentation metadata.
- **Enforcement**:
  - Utilizing `yard stats --list-undoc` inside GitHub CI workflows to monitor documentation coverage. Because `yard stats` defaults to exit code `0` regardless of missing docs, CI pipelines **must explicitly parse the output** (e.g., `grep -q "100.00% documented"`) to strictly fail the build and block the release if any public class, module, or method lacks inline documentation.

## 5. Security: Gem Code Signing and Certificates

Cryptographic signing ensures end-to-end security and integrity verification of the published `.gem` artifacts.

- Inside the `http_loader.gemspec`:
  ```ruby
spec.cert_chain = ['certs/http_loader-public_cert.pem']
spec.signing_key = File.expand_path('~/.gem/gem-private_key.pem') if $PROGRAM_NAME.end_with?('gem') && File.exist?(File.expand_path('~/.gem/gem-private_key.pem'))
  ```
- The public certificate is distributed with the repository.
- The private key is securely stored in CI secrets and dynamically evaluated. It prevents the local `gem build` from failing for developers who do not possess the private key.

## 6. Continuous Integration & Delivery (GitHub Actions)

### CI Verification Pipeline (`ci.yml`)
The workflow operates on every push/PR against a matrix. To maximize bandwidth and minimize feedback loops, verification checks must be partitioned into independent parallel jobs (e.g., `lint`, `test`, `typecheck`, `docs`, `build`) rather than chaining them sequentially:

**Blueprint / Reference for AI Agents:**
```yaml
name: CI
on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]
env:
  FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true # Suppress Node 20 deprecation warnings

jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        ruby: ["2.7", "3.2", "3.3", "4.0"] # Full runtime matrix
    steps:
    - uses: actions/checkout@v6
    - uses: ruby/setup-ruby@v1
      with:
        ruby-version: ${{ matrix.ruby }}
        bundler-cache: true
    - run: bundle exec rspec

  # Repeat the above structure for `lint`, `typecheck`, `docs`, `build` 
  # pinned to the highest Ruby version (e.g. ruby: ["4.0"])
```
1. **Target Matrix Execution**: Runtime execution paths (specifically `test`, which exercises runtime logic including `sorbet-runtime`) must be tested against a full matrix of officially supported Ruby versions (e.g., `ruby: ["2.7", "3.2", "3.3", "4.0"]`) to guarantee backward compatibility across environments. Conversely, static checks and builds (`lint`, `typecheck`, `docs`, `build`) are environment-independent. Static typecheckers (`srb tc`) parse the syntax tree deterministically without relying on the underlying Ruby runtime. Thus, these static checks should be strictly pinned to the highest supported Ruby version (e.g., `ruby: ["4.0"]`) to conserve CI compute bandwidth.
2. **Modern Action Tools**: Always utilize up-to-date, pinned major versions for core actions (e.g., `actions/checkout@v6`, `ruby/setup-ruby@v1`). Actions MUST run natively on Node 24 (or newer) to prevent GitHub runner deprecation warnings caused by legacy environments (e.g., Node 20).
3. **Fast Dependency Tracking**: Setup Ruby and aggressively cache dependencies natively via `bundler-cache: true`.
4. **Linting**: `bundle exec rubocop`
5. **Testing**: `bundle exec rspec`
6. **Typing**: `bundle exec srb tc --typed strong`
7. **Documentation**: Build YARD and run `yard stats --list-undoc`, ensuring the pipeline explicitly checks the output for `100.00% documented` to securely fail on missing documentation.
8. **Integrity checks**: Validating gem builds locally (`gem build`).

### Automated Secure Releases (`release.yml`)
Initiated upon semantic version tagging (`v*.*.*`).

**Blueprint / Reference for AI Agents:**
```yaml
name: Automated Release
on:
  push:
    tags:
      - 'v*.*.*'
env:
  FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true

jobs:
  build_and_release:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      id-token: write # Required for OIDC Trusted Publishing
    steps:
    - uses: actions/checkout@v6
      with:
        fetch-depth: 0
    - uses: ruby/setup-ruby@v1
      with:
        ruby-version: 4.0
        bundler-cache: true
    
    # 1. Safely inject multiline cryptographic key via `env` and `printf`
    - name: Recover Private Key
      env:
        GEM_PRIVATE_KEY: ${{ secrets.GEM_PRIVATE_KEY }}
      run: |
        mkdir -p ~/.gem
        printf '%s\n' "$GEM_PRIVATE_KEY" > ~/.gem/gem-private_key.pem
        chmod 0600 ~/.gem/gem-private_key.pem
        
    # 2. Extract Tag and sync codebase
    - run: echo "VERSION=${GITHUB_REF#refs/tags/v}" >> $GITHUB_ENV
    - run: sed -i "s/T.let('.*', String)/T.let('${{ env.VERSION }}', String)/" lib/rubocop/ai/version.rb
        
    # 3. Manually build to avoid rake constraints
    - run: gem build rubocop-ai.gemspec
      
    - uses: softprops/action-gh-release@v1
      with:
        files: rubocop-ai-${{ env.VERSION }}.gem
        
    # 4. Generate short-lived OIDC Token
    - uses: rubygems/configure-rubygems-credentials@main

    # 5. Push compiled artifact bypassing dirty working tree failures
    - run: gem push rubocop-ai-${{ env.VERSION }}.gem
```
1. **Version synchronisation**: Dynamically replaces the static version string in `lib/.../version.rb` mapped directly from the git tag. Because this alters the git working tree, it explicitly breaks tools that require a "clean" repository (such as `rake release`).
2. **Key Inject**: Reconstructs the code-signing private key `gem-private_key.pem` through GitHub Secrets. **Crucially**, multi-line certificates MUST be injected via environment variables (`env: GEM_PRIVATE_KEY`) and written via `printf '%s\n' "$GEM_PRIVATE_KEY" > ~/.gem/gem-private_key.pem`. Using standard `echo` interpolations will flatten line breaks, corrupting the key and causing `OpenSSL::PKey::PKeyError`.
3. **Release deployment**: Pushes the manually compiled `.gem` artifact to GitHub Releases.
4. **Registry Push (RubyGems)**: Avoid high-level wrapper actions (like `rubygems/release-gem`) which implicitly enforce `bundle exec rake release` standards (requiring an explicit `Rakefile` and a perfectly clean git tree). Instead, leverage `rubygems/configure-rubygems-credentials` to securely initialize OIDC Trusted Publishing (or fallback to `RUBYGEMS_API_KEY` secret), then execute a direct `gem push` on the built artifact. Note: if it's the very first time publishing the gem, a "Pending Trusted Publisher" MUST be created on RubyGems.org beforehand, as `GEM_PRIVATE_KEY` is only for local signing and provides zero network authorization.

## 7. Reliability & Architecture Guidelines (Best Practices)

To make a Ruby project strictly resilient and reliable:
1. **Segregation of Intent**:
   - Dedicate `REQUIREMENTS.md` representing current active specifications uniquely tagged (e.g., `CORE-REQ-001`).
   - Catalog defects explicitly in `BUGS.md` decoupled from standard development tasks.
2. **Immutability First**: Default to `# frozen_string_literal: true`. Never map values loosely.
3. **Fail-Fast Error Handling**: Throw explicit custom library exceptions inside domain boundaries rather than propagating StandardError out un-handled.
4. **Hermetic Testing**: Utilize clock freezes, deterministic PRNGs, and exact mock borders. Never execute network commands in RSpec suites.
5. **Absolute Thread Safety**: When writing multi-concurrency code in Ruby, utilize `Mutex` heavily, avoid mutating class-level/global state variables, and leverage `rubocop-thread_safety` analyzers strictly.

## 8. Environment & Dependency Management

Establishing reproducible development environments relies on explicitly defined configurations:

1. **Ruby Versioning**: **Always target the latest available Ruby version.** Track the exact Ruby version using a `.ruby-version` file to ensure parity between developer machines and CI contexts. Modern toolchains (like `mise` or `rbenv`) naturally ingest this.
2. **Dependency Pinning (Gemspec vs. Gemfile)**:
   - For reusable generic libraries (gems), do NOT commit `Gemfile.lock` to version control. This ensures CI pipelines resolve the appropriate, environment-compatible dependencies during multi-version matrix tests.
   - Maintain all dependencies (runtime and development) strictly within the `gemspec`. The `Gemfile` should only contain `gemspec`.
   - Default to safe version bounds utilizing the pessimistic operator (`~> x.y`) inside the `gemspec`. However, if there is a possibility that the gem works across multiple major versions of a dependency (e.g., standard tooling like `rubocop`, `rspec`, or `rake`), use `>=` to avoid aggressively over-constraining testing dependencies.
3. **Gemspec File Generation**: Never use `git ls-files` or similar shell commands to populate `spec.files`. Rely on native Ruby globbing (e.g., `Dir.glob('{exe,lib,certs,config}/**/*')`) to ensure the gem can be successfully built in environments without a `.git` directory or git executable.
   - **Configuration Exposure Requirement**: If the gem is a plugin or actively distributes configuration defaults (e.g., RuboCop extensions needing `config/default.yml`), it is critical to explicitly append `config` (or the relative metadata directory) to the `Dir.glob` definition. Failure to do so will compile a valid-looking package that silently omits critical configuration structures, leading to file-not-found exceptions upon production install.
4. **Environment Determinism**: Enforce locale semantics explicitly (e.g., establishing `ENV['LANG'] = ENV.fetch('LANG', 'en_US.UTF-8')` statically in Rakefiles or CI configurations) to avert subtle encoding failures across distributed platforms.
5. **Version Control Ignore Policies (`.gitignore`)**: Safely partition exclusion files utilizing explicitly commented boundary sections: OS / Editor artifacts, Ruby / Bundler extractions (`*.gem`, `vendor/`), Logs and Output, Coverage caches, YARD document generation caches (`.yardoc/`), and general transient formats (e.g. `*.json`). Conform to these categories rigidly to maintain repository cleanliness.

## 9. Gem Metadata Standards

Consistent metadata helps standardize open-source publication and internal tracking.

1. **Homepage Template**: Set the `spec.homepage` strictly utilizing the HTTPS standard GitHub web URI format: `https://github.com/VitaliiLazebnyi/<gem name>`.
2. **Minimize Metadata Link Duplication**: Do NOT duplicate the `spec.homepage` value into `spec.metadata['homepage_uri']`. RubyGems versions emit warnings when there are multiple metadata fields (like `homepage_uri` and `source_code_uri`) assigning the exact same URI, as it will deduplicate them visually on rubygems.org. Standard practice is to provide `spec.homepage` inherently, set `spec.metadata['source_code_uri'] = spec.homepage` to explicitly activate the source code link, and omit `homepage_uri` from the metadata hash.
