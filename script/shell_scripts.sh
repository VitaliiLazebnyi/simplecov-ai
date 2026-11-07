#!/usr/bin/env bash
# Prints every tracked shell script, one per line: the *.sh files and the extensionless files
# whose shebang names bash or sh (the Git hook, bin/). ShellCheck and shfmt run on this list
# (CI, script/check).
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

git ls-files -z | while IFS= read -r -d '' file; do
  case "${file##*/}" in
  *.sh) printf '%s\n' "${file}" ;;
  *.*) ;;
  *) if head -n 1 -- "${file}" | grep -Eq '^#!.*\b(bash|sh)\b'; then printf '%s\n' "${file}"; fi ;;
  esac
done
