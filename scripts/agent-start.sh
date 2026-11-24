#!/usr/bin/env bash
# First command of every scheduled agent run (see the run-start skill).
#   agent-start.sh <kind> [persona]
# Fetches both repos, starts run metadata, installs the pre-push hook, runs preflight, switches to the persona's
# GitHub App when this environment holds its key (persona is the argument, else AGENT_PERSONA; a shared
# environment needs the argument; a persona is a role key from crew.json), prints active lessons.
# Exit 1 on a preflight or identity FAIL.
# Shortcut: an environment with no App key at all still runs as the owner; drop that once every key is set.
set -uo pipefail
. "$(dirname "$0")/lib/crew-env.sh"
here="$(cd "$(dirname "$0")" && pwd)"
kind="${1:?usage: agent-start.sh <kind> [persona]}"
MAIN="${CREW_MAIN_BRANCH:-main}"
checkouts() { printf '%s\n' "$CREW_PLAN_DIR"; [ "$CREW_CODE_DIR" = "$CREW_PLAN_DIR" ] || printf '%s\n' "$CREW_CODE_DIR"; }

# Fresh origin/main first: lessons and gates read it (a stale view cost a worker two minutes, observed).
while IFS= read -r d; do git -C "$d" fetch -q origin || echo "WARN   git-fetch      failed in $d"; done < <(checkouts)
# A cron VM can start on a stale scratch branch, and plan-status scripts read the working tree: runs claimed an
# already-archived change (observed). Move a clean, fully pushed scratch checkout to origin/main.
while IFS= read -r d; do
  g() { git -C "$d" "$@"; }
  b=$(g branch --show-current)
  if { [ -z "$b" ] || [[ "$b" == claude/* && ! "$b" =~ ^claude/(change|planning|lead|fix-main)- ]]; } &&
    ! g rev-parse -q --verify "origin/$b" >/dev/null &&
    [ -z "$(g status --porcelain)" ] && [ -z "$(g rev-list -n1 HEAD --not --remotes)" ] &&
    [ "$(g rev-parse HEAD)" != "$(g rev-parse "origin/$MAIN")" ]; then
    if [ -n "$b" ]; then g checkout -q -B "$b" "origin/$MAIN"; else g checkout -q --detach "origin/$MAIN"; fi &&
      echo "OK     checkout       stale ${b:-detached HEAD} moved to origin/$MAIN in $d"
  fi
done < <(checkouts)
bash "$here/run-meta.sh" start "$kind"
# Ticks need an evaluator PASS before they leave the VM (run-meta.sh push-check); keep any existing hook.
# The hook runs the harness checkout's copy, so a change branch that predates push-check can still push.
while IFS= read -r d; do
  hook="$(cd "$d" && cd "$(git rev-parse --git-common-dir)" && pwd)/hooks/pre-push"
  mkdir -p "$(dirname "$hook")"
  [ -e "$hook" ] || {
    printf '#!/bin/sh\nCREW_CONFIG=%q CREW_PLAN_DIR=%q CREW_CODE_DIR=%q bash %q push-check\n' \
      "$CREW_CONFIG" "$CREW_PLAN_DIR" "$CREW_CODE_DIR" "$here/run-meta.sh" > "$hook" && chmod +x "$hook"
  }
done < <(checkouts)
echo "== preflight"
bash "$here/agent-preflight.sh"; pf=$?
persona="${2:-${AGENT_PERSONA:-}}"; var=AGENT_APP_KEY_
# a project may name its key variable per role in crew.json (roles.<role>.key_env); AGENT_APP_KEY_<ROLE> also works
[ -n "$persona" ] && var=$(bash "$here/agent-identity.sh" keyvar "$persona")
echo "== identity"
if [ -n "$persona" ] && [ -n "${!var:-}" ]; then
  # A key is set, so a run must never fall back to the owner: setup undoes itself and prints FAIL on any error.
  bash "$here/agent-identity.sh" setup "$persona" || pf=1
elif compgen -v AGENT_APP_KEY_ >/dev/null; then
  # Keys here but none for this persona (often a routine that forgot to pass it): never fall back to the owner.
  echo "FAIL identity: this environment holds App keys but $([ -n "$persona" ] && echo "no $var" || echo "no persona was passed"); run agent-start.sh $kind <persona>"; pf=1
elif [ "$kind" = research ] || [ "$persona" = research ]; then
  echo "FAIL identity: research has open internet and never runs as the owner; set $var"; pf=1
else echo "WARN   identity: no ${persona:+$var }key in this environment; acting as the owner account"; fi
echo "== active lessons ($PATH_LESSONS on origin/$MAIN of the plan repo)"
lessons=$(crew_plan_git show "origin/$MAIN:$PATH_LESSONS" 2>/dev/null | awk '/^## L[0-9]+/{p=1} p')
echo "${lessons:-(none)}"
exit "$pf"
