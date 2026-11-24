#!/usr/bin/env bash
# Cheap "is there anything to do?" check so idle worker runs exit in seconds (idle agents spend nothing).
# Exit 0 and print the reasons when there is work; exit 1 and print "idle" when there is none.
# PRs, CI runs and reviews are read from the code repo; change status and planning PRs from the plan repo.
#   scripts/worker-has-work.sh [role]   (role: the worker's crew.json role key; default AGENT_PERSONA)
set -uo pipefail
. "$(dirname "$0")/lib/crew-env.sh"
ci_file=${CREW_CI_FILE:-ci.yml}  # the CI workflow file in the code repo
work=()
# An open harness-blocker labelled hold-workers stops every worker run (owner tags excepted) and any dispatcher that
# runs this script before it fires a worker.
[ "$(gh api "repos/$PLAN_REPO/issues?labels=harness-blocker,hold-workers&state=open&per_page=1" -q length 2>/dev/null)" = 1 ] && { echo idle; exit 1; }
crew_plan_git fetch -q origin 2>/dev/null; crew_code_git fetch -q origin 2>/dev/null
# A worker acts only on PRs it opened; without a persona (no App identities) count every PR.
AGENT_PERSONA=${1:-${AGENT_PERSONA:-$(cat "${AGENT_ID_DIR:-$HOME/.config/crew-agent}/persona" 2>/dev/null)}}  # $1: this runs before agent-start.sh records it
export AGENT_PERSONA  # change-status.sh needs it too, or a worker's own change PR reads as owned by another (observed 2026-11)
me=${AGENT_PERSONA:+$(crew_role_logins "$AGENT_PERSONA")}  # one login per line
# shellcheck disable=SC2016 # jq variables
mine='select(env.me == "" or (.user.login as $l | env.me | split("\n") | index($l)))'; export me

# Your PRs whose merge review failed (fix the findings first)
n=$(gh api "repos/$CODE_REPO/issues?labels=review-failed&state=open" -q "[.[]|select(.pull_request)|$mine]|length")
[ "$n" -gt 0 ] && work+=("$n of your PR(s) failed merge review")

# Red main CI
c=$(gh api "repos/$CODE_REPO/actions/workflows/$ci_file/runs?branch=main&per_page=1" -q '.workflow_runs[0].conclusion // ""')
[ "$c" = failure ] && work+=("main CI is red")

# Open change PRs whose latest ci run failed (fix them first), unless an open needs-rescue issue names the change
# (matched like change-status.sh): the lead has it, so waking a worker for it is wasted.
rescues=$(gh api "repos/$PLAN_REPO/issues?labels=needs-rescue&state=open&per_page=100" -q '.[]|(.title+" "+(.body // ""))|gsub("\n";" ")' 2>/dev/null)
for b in $(gh api "repos/$CODE_REPO/pulls?state=open&per_page=100" -q ".[]|$mine|.head.ref|select(startswith(\"claude/change-\"))"); do
  [ -n "$rescues" ] && grep -qF -- "${b#claude/change-}" <<<"$rescues" && continue
  r=$(gh api "repos/$CODE_REPO/actions/workflows/$ci_file/runs?branch=$b&per_page=1" -q '.workflow_runs[0].conclusion // ""')
  [ "$r" = failure ] && work+=("CI is red on $b")
done

# Changes a worker may take now (dependency-aware, not parked, not claimed), and finished ones to archive.
status=$(bash "$(dirname "$0")/change-status.sh")
while IFS=$'\t' read -r id state _; do
  case "$state" in
    ready|stackable) work+=("$id is $state") ;;
    finished) work+=("$id is finished but not archived") ;;
  esac
done <<<"$status"

# Plan ahead: with fewer than three takeable changes (one per scheduled worker; parallel work first), no open
# planning PR, and a roadmap row whose Needs are met, writing that row is work. Planning PRs are plan-repo PRs.
next=$(bash "$(dirname "$0")/change-status.sh" --plannable | head -1)
takeable=$(grep -cE $'\t(ready|stackable)\t' <<<"$status" || true)
plans=$(gh api "repos/$PLAN_REPO/pulls?state=open&per_page=100" -q '.[]|select(.head.ref|startswith("claude/planning-"))|[.number, (.auto_merge != null)]|@tsv')
[ "${takeable:-0}" -lt 3 ] && [ -z "$plans" ] && [ -n "$next" ] && work+=("fewer than 3 changes ready: plan the next one ($next)")
# A planning PR without auto-merge never merges and also suppresses planning, so workers would idle forever.
while IFS=$'\t' read -r pr auto; do
  [ "$auto" = false ] && work+=("planning PR #$pr does not have auto-merge on")
done <<<"$plans"

if [ "${#work[@]}" -gt 0 ]; then printf 'work: %s\n' "${work[@]}"; exit 0; fi
echo idle; exit 1
