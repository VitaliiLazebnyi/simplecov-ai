# shellcheck shell=bash
# The definition of a warning, shared by the CI warning gate (script/warning_gate.sh) and
# script/check: any line saying warning or deprecation, in any of the forms tools print them.
#
# Usage: warning_lines < log   (prints every warning line of the log with its line number)
warning_lines() {
  local pattern
  pattern='[Ww]arning:|WARNING:|\bWARN\b|::warning|##\[warning\]'
  pattern+='|DEPRECATION|DEPRECATED|is deprecated|will be deprecated|Node\.js [0-9]+ actions are deprecated'
  # Upstream output that matches but is no warning about this repository, each line matched in
  # full; the same words anywhere else still fail:
  # - CodeQL prints the JSON schema of its extractor options, whose "title" and "description"
  #   fields document a deprecated option ("DEPRECATED - Whether to use buildless ...");
  # - the Harden-Runner agent, whose post step prints its log: on Linux, dpkg's notice when the
  #   agent uninstalls Docker (disable-sudo-and-containers) from the runner image; on Windows,
  #   its process monitor noting a reused process ID;
  # - the dependency review, which reports a dependency whose own OpenSSF Scorecard is below 3 (the
  #   transitive npm packages of markdownlint-cli2) as a warning: a property of the upstream
  #   project, not a finding about this repository.
  local timestamp='^[0-9]+:[0-9TZ:.-]+ +'
  local codeql_schema="${timestamp}\"(title|description)\" : \""
  local dpkg_notice="${timestamp}[A-Z][a-z]{2}, [0-9]{2} [A-Z][a-z]{2} [0-9]{4} [0-9:]{8} GMT:dpkg: warning: "
  dpkg_notice+="while removing docker-ce, directory '/usr/libexec/docker' not empty so not removed[[:space:]]*$"
  local reused_pid="${timestamp}time=[0-9TZ:.-]+ level=WARN "
  reused_pid+='msg="(pid reused|existing process not stopped, resetting it)" '
  reused_pid+='pid=[0-9]+ exe=[^ ]+ existingExe=[^ ]+ existingStartTime=[0-9TZ:.-]+[[:space:]]*$'
  local low_scorecard="${timestamp}##\[warning\][a-z]+/[^ ]+ has an OpenSSF Scorecard of [0-9.]+, "
  low_scorecard+="which is less than this repository's threshold of 3\.$"
  local upstream=("${codeql_schema}" "${dpkg_notice}" "${reused_pid}" "${low_scorecard}")
  local exceptions
  exceptions=$(IFS='|' && printf '%s' "${upstream[*]}")
  grep -nE -e "${pattern}" | grep -vE -e "${exceptions}" || true
}
