#!/usr/bin/env bash
# Runs the three issue syncs (change-sync, roadmap-sync, dates-sync) from a clean checkout of the plan
# repo's main branch, so an agent can run it from any branch without its unmerged edits reaching GitHub.
# The lead runs this at the end of every run while the change-sync workflow is off.
#   scripts/issues-sync.sh            DRY_RUN=1 prints the writes instead of making them
#   CREW_PLAN_BRANCH overrides the branch (default main)
set -euo pipefail
. "$(dirname "$0")/lib/crew-env.sh"
scripts=$(cd "$(dirname "$0")" && pwd); br=${CREW_PLAN_BRANCH:-main}
cd "$CREW_PLAN_DIR"
git fetch -q origin "$br"
d=$(mktemp -d)
trap 'git -C "$CREW_PLAN_DIR" worktree remove --force "$d"' EXIT
git worktree add -q --detach "$d" "origin/$br"
# The syncs read plan files from CREW_PLAN_DIR, so point them at the clean checkout.
export CREW_PLAN_DIR=$d CREW_CONFIG=$d/crew.json
for s in change-sync roadmap-sync dates-sync; do
  if [ -f "$scripts/$s.sh" ]; then bash "$scripts/$s.sh"; else echo "issues-sync: $s.sh not present, skipped"; fi
done
