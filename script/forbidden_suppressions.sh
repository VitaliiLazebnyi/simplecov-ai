#!/usr/bin/env bash
# Fails when a tracked file silences a linter, scanner, type checker, coverage tool, warning or
# test, or weakens typing. Inline suppressions are forbidden everywhere in this repository (see
# CONTRIBUTING.md): fix the cause. A rule that cannot apply to a file is configured narrowly in
# the tool's configuration file instead, with the reason next to it.
#
# Markdown files are not scanned: they document these rules and the gem's own bypass audit.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# This script names the patterns, so it is not scanned for them.
files=$(git ls-files -z -- . ':(exclude)*.md' ':(exclude)script/forbidden_suppressions.sh' | tr '\0' '\n')

status=0
check() {
  local description=$1 pattern=$2 scope=${3:-.}
  local hits
  hits=$(printf '%s\n' "$files" | grep -E "^${scope}" | xargs -r grep -nEH -e "$pattern" -- || true)
  if [ -n "$hits" ]; then
    printf 'Forbidden (%s):\n%s\n\n' "$description" "$hits"
    status=1
  fi
}

check 'RuboCop directive' 'rubocop:(disable|enable|todo)'
check 'RuboCop todo file' 'inherit_from:.*todo'
check 'Reek suppression' ':reek:'
# The two directive forms SimpleCov honours: a nocov toggle at the start of a comment line, and
# a simplecov:disable comment anywhere on a line (SimpleCov >= 1.0). Coverage is measured for
# lib/ only (spec/spec_helper.rb skips everything else), so that is where a directive could take
# code out of a figure; the specs and fixtures quote directives as test data for the gem's own
# bypass audit. spec/quality/self_audit_spec.rb additionally asks SimpleCov itself whether it
# skips anything in lib/.
check 'SimpleCov nocov directive' '^[[:space:]]*#[[:space:]]*:nocov:' 'lib/'
check 'SimpleCov disable directive' '#[[:space:]]*simplecov[[:space:]]*:[[:space:]]*disable' 'lib/'
check 'mutant suppression' 'mutant:disable'
check 'gitleaks allow' 'gitleaks:allow'
check 'zizmor ignore' 'zizmor: ?ignore'
check 'shellcheck disable' 'shellcheck +disable'
check 'typos ignore' 'typos: ?(ignore|off)|spellchecker: ?disable'
check 'markdownlint directive' 'markdownlint-(disable|capture|configure-file)'
check 'Semgrep suppression' 'nosemgrep'
check 'LGTM/CodeQL suppression' 'lgtm\[|codeql\[|codeql-disable|lgtm: ?ignore'
check 'nosec' 'nosec'
check 'warning silencing' '[$]VERBOSE *= *(nil|false)|Warning\.ignore|Warning\[[^]]*\] *= *false|silence_warnings|[$]stderr *= *File::NULL|-W0'
check 'skipped or focused test' '^[[:space:]]*([xf](it|specify|example|describe|context)|skip|pending)([[:space:]]|\(|$)|focus: *true|, *:focus|, *(skip|pending): ' 'spec/'
check 'Sorbet escape hatch' 'T\.(unsafe|cast|bind|must|untyped)\b|T::Utils\.run_all_sig_blocks|T::Configuration' 'lib/'
check 'Sorbet sigil below strict' 'typed: *(ignore|false|true)\b' 'lib/'
check 'CI step allowed to fail' 'continue-on-error: *true' '.github/'

exit "$status"
