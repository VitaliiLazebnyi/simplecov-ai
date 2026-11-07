# shellcheck shell=bash
# The definition of a warning, shared by the CI warning gate (script/warning_gate.sh) and
# script/check: any line saying warning or deprecation, in any of the forms tools print them.
#
# Usage: warning_lines < log   (prints every warning line of the log with its line number)
warning_lines() {
  local pattern documentation
  pattern='[Ww]arning:|WARNING:|\bWARN\b|::warning|##\[warning\]'
  pattern+='|DEPRECATION|DEPRECATED|is deprecated|will be deprecated|Node\.js [0-9]+ actions are deprecated'
  # The one kind of matching line that is not a warning: CodeQL prints the JSON schema of its
  # extractor options, whose "title" and "description" fields document a deprecated option
  # ("DEPRECATED - Whether to use buildless ..."). Only such JSON documentation fields are
  # skipped; the same words anywhere else still fail.
  documentation='^[0-9TZ:.-]+ +"(title|description)" : "'
  grep -nE -e "${pattern}" | grep -vE -e "^[0-9]+:${documentation#^}" || true
}
