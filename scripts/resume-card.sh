#!/usr/bin/env bash
# Where one change stands, as a short card, so a run starts from facts bash gathered instead of whole-file reads
# and a dozen orientation turns (each turn re-sends everything read before it). Read a file in full only when a
# task needs more than the card shows.
#   scripts/resume-card.sh <change-id>      (AGENT_PERSONA: the caller's role, as for change-status.sh)
# Sections: state, open tasks, last progress entry, code PRs (author, CI, merge review), plan PRs (CI).
# Every section is capped: comments and CI text are third-party data and must not flood the context.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/crew-env.sh
. "$here/lib/crew-env.sh"
id=${1:?usage: resume-card.sh <change-id>}
cap() { cut -c1-"${2:-200}" | head -n "$1"; }  # cap <lines> [chars per line]
cd "$CREW_PLAN_DIR" || exit 2
CH=${PATH_CHANGES%/}
crew_plan_git fetch -q origin 2>/dev/null; crew_code_git fetch -q origin 2>/dev/null
AGENT_PERSONA=${AGENT_PERSONA:-$(cat "${AGENT_ID_DIR:-$HOME/.config/crew-agent}/persona" 2>/dev/null)}
export AGENT_PERSONA
me=${AGENT_PERSONA:+$(crew_role_logins "$AGENT_PERSONA")}

echo "== $id"
bash "$here/change-status.sh" 2>/dev/null | awk -F'\t' -v id="$id" '$1==id{print "state: " $2 ($3 != "" ? " (" $3 ")" : "")}'

# Tasks and progress from the newest plan branch of the change (where unmerged ticks live, as in change-status.sh),
# else the checkout.
b=$(crew_plan_git for-each-ref --sort=-committerdate --count=1 --format='%(refname:short)' \
  "refs/remotes/origin/claude/change-$id" "refs/remotes/origin/claude/change-$id-r*")
plan_file() { { [ -n "$b" ] && crew_plan_git show "$b:$CH/$id/$1" 2>/dev/null; } || cat "$CH/$id/$1" 2>/dev/null; }
t=$(plan_file tasks.md)
[ -n "$t" ] || { echo "no tasks.md for $id"; exit 1; }
echo "tasks: $(grep -cE '^\s*- \[x\]' <<<"$t") done, $(grep -cE '^\s*- \[ \]' <<<"$t") open (from ${b:-checkout})"
open=$(awk '/^## /{h=$0; next} /^\s*- \[ \]/{if (h != "") print h; h=""; print}' <<<"$t")
cap 25 <<<"$open"; [ "$(wc -l <<<"$open")" -gt 25 ] && echo "(more open tasks: read tasks.md when you get there)"
echo "-- last progress entry"
plan_file progress.md | awk '/^## /{e=""} {e = e $0 "\n"} END{printf "%s", e}' | cap 12
echo "-- code branch"
crew_code_git log --oneline -5 "origin/claude/change-$id" 2>/dev/null | cap 5 100

# Open PRs on claude/change-<id> or its -r<n> rebranches, in the code repo and the plan repo.
export B="claude/change-$id"
prs() { gh api "repos/$1/pulls?state=open&per_page=100" \
  -q '.[]|select(.head.ref|test("^" + env.B + "(-r[0-9]+)?$"))|[.number, .head.ref, .user.login, (.auto_merge != null)]|@tsv' 2>/dev/null; }
while IFS=$'\t' read -r n ref who auto; do
  [ -n "$n" ] || continue
  own=yours; [ -n "$me" ] && ! grep -qxF "$who" <<<"$me" && own="NOT YOURS"
  echo "-- code PR #$n $ref by $who ($own), auto-merge: $auto"
  bash "$here/ci-failures.sh" "$n" 2>/dev/null | cap 10
  # The newest merge-review verdict; a FAIL keeps its findings (truncated).
  gh api "repos/$CODE_REPO/issues/$n/comments?per_page=100" \
    -q '[.[]|select(.body|test("merge-review [0-9a-f]{7,40}: (PASS|FAIL)"))]|last|.body // empty' 2>/dev/null |
    sed 's/^<!--[^>]*-->[[:space:]]*//' | awk 'NF' | awk 'NR==1 && !/FAIL/{print; exit} {print}' | cap 8 300
done < <(prs "$CODE_REPO")
while IFS=$'\t' read -r n ref who _; do
  [ -n "$n" ] || continue
  echo "-- plan PR #$n $ref by $who"
  bash "$here/ci-failures.sh" "$n" -R "$PLAN_REPO" 2>/dev/null | cap 6
done < <(prs "$PLAN_REPO")
exit 0
