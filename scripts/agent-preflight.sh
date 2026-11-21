#!/usr/bin/env bash
# Preflight for scheduled agents: find environment problems in seconds instead of minutes into a run.
# Fixes what is safe (a check's own `fix` command); reports the rest. One line per check:
#   OK / FIXED / WARN / FAIL <hint>. Exit 0 unless a check at level `fail` FAILs.
# Tool checks come from crew.json `.preflight`, an array of
#   {"name":"docker","cmd":"docker info","fix":"$SUDO dockerd &","level":"warn|fail","hint":"...","wait":20}
# cmd must exit 0 when the tool is fine. If it does not and `fix` is set, the fix runs (in the code checkout,
# output discarded, $SUDO is "" as root and "sudo -n" otherwise), then cmd is polled up to `wait` seconds
# (default 20). level defaults to fail; hint is optional text shown when the check still fails.
# Built in: gh auth, GitHub API reachability, free disk (PREFLIGHT_MIN_DISK_GB, default 5).
set -uo pipefail
. "$(dirname "$0")/lib/crew-env.sh"
fail=0
say() { printf '%-6s %-14s %s\n' "$1" "$2" "${3:-}"; }
if [ "$(id -u)" = 0 ]; then SUDO=""; else SUDO="sudo -n"; fi; export SUDO
cd "$CREW_CODE_DIR" || { say FAIL checkout "cannot cd to $CREW_CODE_DIR"; exit 1; }

poll() { # <cmd> <seconds>: true once cmd passes
  local c="$1" n="$2" i=0
  while :; do bash -c "$c" </dev/null >/dev/null 2>&1 && return 0; i=$((i+1)); [ "$i" -gt "$n" ] && return 1; sleep 1; done
}
while IFS=$'\x1f' read -r name cmd fix level hint wait; do
  [ -n "$name" ] || continue
  level="${level:-fail}"; wait="${wait:-20}"
  if bash -c "$cmd" </dev/null >/dev/null 2>&1; then say OK "$name"; continue; fi
  if [ -n "$fix" ]; then
    bash -c "$fix" </dev/null >/dev/null 2>&1
    if poll "$cmd" "$wait"; then say FIXED "$name" "fixed by: $fix"; continue; fi
  fi
  if [ "$level" = warn ]; then say WARN "$name" "${hint:-check failed: $cmd}"; else say FAIL "$name" "${hint:-check failed: $cmd}"; fail=1; fi
done < <(jq -r '.preflight[]? | [.name, .cmd, (.fix // ""), (.level // ""), (.hint // ""), (.wait // "" | tostring)] | join("\u001f")' "$CREW_CONFIG")

# disk (build caches fill small cloud VMs fast)
min="${PREFLIGHT_MIN_DISK_GB:-5}"
avail=$(df -Pk . | awk 'NR==2 {print int($4/1048576)}')
if [ "${avail:-0}" -ge "$min" ]; then say OK disk "${avail} GB free"; else say WARN disk "${avail} GB free (want ${min}): free build caches before a long build"; fi

# network: the GitHub API must be reachable (an environment allowlist problem shows up here, not 10 minutes in)
if curl -fsS -m 8 -o /dev/null https://api.github.com/; then say OK net "https://api.github.com/"; else say WARN net "https://api.github.com/ unreachable (environment allowlist?)"; fi

# GitHub auth through the cloud proxy (REST)
if gh api rate_limit >/dev/null 2>&1; then say OK gh-api; else say WARN gh-api "gh api failed"; fi

exit "$fail"
