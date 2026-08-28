# Security Policy

## Supported versions

Security fixes are applied to the latest released `0.11.x` line.

| Version | Supported |
| ------- | --------- |
| 0.11.x  | ✅        |
| < 0.11  | ❌        |

## Reporting a vulnerability

Please report suspected vulnerabilities privately rather than opening a public issue.

- Preferred: use GitHub's **"Report a vulnerability"** flow under the repository's *Security*
  tab (private advisories).
- Alternatively, email <vitalii.lazebnyi.github@gmail.com> with the details.

Include a description of the issue, the affected version(s), and a minimal reproduction if
possible. You can expect an acknowledgement within a few business days. Once a fix is prepared,
a patched release will be published to RubyGems and the advisory disclosed.

## Scope notes

simplecov-ai reads project source files and coverage results and writes a Markdown report. It
does not execute project code, open network connections, or run in production. The most relevant
consideration is that uncovered source snippets are copied verbatim into the generated report; if
that report is fed to an autonomous agent, treat the source content as untrusted input to the
consumer just as you would any other source file.

Since 0.11.0 every value taken from a source file or its coverage data — snippets, method and
class names, file paths, branch types and the `# :nocov:` / `# simplecov:disable` comments quoted
as bypass reasons — is rendered as a CommonMark code span whose backtick fence is longer than any
backtick run inside the value, so a comment cannot close the span early and inject headings,
emphasis or list items into the report's structure. This containment keeps the report's *shape*
under the formatter's control; it does not make the *content* trustworthy. A comment reading
"ignore all previous instructions" still appears, verbatim, inside a code span, and the consumer
must treat it as data.

On SimpleCov < 1.0, branch descriptors read back from `coverage/.resultset.json` are decoded by
SimpleCov's own `eval`-based `restore_ruby_data_structure` helper (which simplecov-ai calls
through a `respond_to?` guard). A tampered resultset file can therefore execute Ruby inside the
test process on those versions, so treat `coverage/.resultset.json` as a trust boundary there:
do not merge or format resultsets from untrusted sources. SimpleCov 1.0 replaced that helper
with a dedicated parser (`SimpleCov::SourceFile::RubyDataParser`), removing the `eval`.

## Supply-chain safeguards

Releases are built by the tag-triggered workflow only after every quality gate passes, published
to RubyGems through OIDC trusted publishing, and signed with the certificate in `certs/`. CI runs
`bundler-audit`, Semgrep, Gitleaks, CodeQL, zizmor and the OpenSSF Scorecard; all GitHub Actions
are pinned to full commit SHAs and updated by Dependabot with a one-week cooldown.
