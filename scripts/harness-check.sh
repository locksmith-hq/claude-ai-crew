#!/usr/bin/env bash
# Local stack check: runs the project's own checks and prints one PASS/FAIL line each. Exit 1 on any FAIL.
# The checks come from crew.json `.stack_checks`, an array of {"name": "...", "cmd": "..."}; each cmd runs in
# the code checkout and passes when it exits 0. No `.stack_checks` means nothing to check (exit 0).
set -uo pipefail
. "$(dirname "$0")/lib/crew-env.sh"
cd "$CREW_CODE_DIR" || exit 2
fail=0
while IFS=$'\t' read -r name cmd; do
  [ -n "$name" ] || continue
  if bash -c "$cmd" </dev/null >/dev/null 2>&1; then echo "PASS  $name"; else echo "FAIL  $name"; fail=1; fi
done < <(jq -r '.stack_checks[]? | [.name, .cmd] | @tsv' "$CREW_CONFIG")
exit "$fail"
