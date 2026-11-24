#!/usr/bin/env bash
# Shared environment for every crew script. Source it, do not run it:
#   . "$(dirname "$0")/lib/crew-env.sh"
#
# It finds the three repos a run works with, loads the domain pack (crew.json) and exports:
#   CREW_HARNESS_DIR  this harness checkout
#   CREW_PLAN_DIR     the plan repo checkout (holds crew.json, roadmap, changes, rules, lessons)
#   CREW_CODE_DIR     the code repo checkout the agents change (first entry of repos.code)
#   CREW_CONFIG       path to crew.json
#   PLAN_REPO / CODE_REPO   "owner/name" for GitHub API calls
#   OWNER_LOGIN, QUICK_CHECK, FULL_CI, and the PATH_* variables below
# Plan repo = coordination: change-tracking issues, locks, help channels, plan files.
# Code repo = PRs, branches, CI runs.
#
# Resolution order for each checkout: the CREW_*_DIR variable, then a git repo under CREW_WORKSPACE
# (default: the current directory, its parent and $HOME) whose origin matches the configured owner/name.
# CREW_PLAN_DIR (or a crew.json in the current directory or its parent) bootstraps everything else.

crew_die() { echo "crew-env: $*" >&2; exit "${CREW_EXIT:-2}"; }
command -v jq >/dev/null 2>&1 || crew_die "jq is required"

CREW_HARNESS_DIR="${CREW_HARNESS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# crew_find_repo owner/name -> prints the checkout directory (or nothing)
crew_find_repo() {
  local want="$1" root d url
  for root in "${CREW_WORKSPACE:-}" "$PWD" "$PWD/.." "$HOME"; do
    [ -n "$root" ] && [ -d "$root" ] || continue
    for d in "$root" "$root"/*/; do
      [ -d "$d/.git" ] || [ -f "$d/.git" ] || continue
      url=$(git -C "$d" config --get remote.origin.url 2>/dev/null) || continue
      case "${url%.git}" in *"/$want"|*":$want") (cd "$d" && pwd); return 0 ;; esac
    done
  done
  return 1
}

# Bootstrap the config.
if [ -z "${CREW_CONFIG:-}" ]; then
  if [ -n "${CREW_PLAN_DIR:-}" ] && [ -f "$CREW_PLAN_DIR/crew.json" ]; then CREW_CONFIG="$CREW_PLAN_DIR/crew.json"
  elif [ -f "$PWD/crew.json" ]; then CREW_CONFIG="$PWD/crew.json"
  elif [ -f "$PWD/../crew.json" ]; then CREW_CONFIG="$(cd "$PWD/.." && pwd)/crew.json"
  else crew_die "no crew.json: set CREW_CONFIG or CREW_PLAN_DIR"; fi
fi
[ -f "$CREW_CONFIG" ] || crew_die "CREW_CONFIG does not exist: $CREW_CONFIG"
export CREW_CONFIG

# crew_get <jq filter> [default]: prints the value or the default
crew_get() { local v; v=$(jq -r "$1 // empty" "$CREW_CONFIG" 2>/dev/null); [ -n "$v" ] && echo "$v" || echo "${2:-}"; }

PLAN_REPO=$(crew_get '.repos.plan'); CODE_REPO=$(crew_get '.repos.code[0]')
[ -n "$PLAN_REPO" ] && [ -n "$CODE_REPO" ] || crew_die "crew.json needs repos.plan and repos.code[0]"
OWNER_LOGIN=$(crew_get '.owner.login'); QUICK_CHECK=$(crew_get '.commands.quick'); FULL_CI=$(crew_get '.commands.ci')
PATH_DECISIONS=$(crew_get '.paths.decisions' decisions.md); PATH_OWNER_RULES=$(crew_get '.paths.owner_rules' owner.md)
PATH_LESSONS=$(crew_get '.paths.lessons' lessons.md); PATH_ROADMAP=$(crew_get '.paths.roadmap' roadmap.md)
PATH_CHANGES=$(crew_get '.paths.changes' changes/)

CREW_PLAN_DIR="${CREW_PLAN_DIR:-$(dirname "$CREW_CONFIG")}"
CREW_CODE_DIR="${CREW_CODE_DIR:-$(crew_find_repo "$CODE_REPO" || true)}"
[ -n "$CREW_CODE_DIR" ] || CREW_CODE_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
export CREW_HARNESS_DIR CREW_PLAN_DIR CREW_CODE_DIR PLAN_REPO CODE_REPO OWNER_LOGIN QUICK_CHECK FULL_CI \
  PATH_DECISIONS PATH_OWNER_RULES PATH_LESSONS PATH_ROADMAP PATH_CHANGES

# git helpers bound to each checkout
crew_plan_git() { git -C "$CREW_PLAN_DIR" "$@"; }
crew_code_git() { git -C "$CREW_CODE_DIR" "$@"; }
# crew_role_login <role>: the GitHub login of a role's App bot ("<app>[bot]"), empty if undefined
crew_role_login() { local a; a=$(crew_get ".roles[\"$1\"].app"); [ -n "$a" ] && echo "${a}[bot]"; }
# crew_role_logins <role>: every login of a role, one per line: "<app>[bot]" first, then roles.<role>.logins (old
# logins kept after an App rename, so earlier PRs and comments still map to the role)
crew_role_logins() { jq -r --arg r "$1" '.roles[$r] // {} | ((if .app then .app + "[bot]" else empty end), (.logins // [])[])' "$CREW_CONFIG" | awk 'NF && !seen[$0]++'; }
