#!/usr/bin/env bash
# Self-test for scripts/change-status.sh: a throwaway plan repo (crew.json, roadmap, changes, branch refs) and an
# empty code repo; no network (OFFLINE=1, issue lists passed in BLOCKERS).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; script="$HERE/../scripts/change-status.sh"; pass=0; failn=0
ok() { echo "ok   $1"; pass=$((pass+1)); }; no() { echo "FAIL $1"; failn=$((failn+1)); }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT; P="$W/plan"; C="$W/code"; mkdir -p "$P" "$C"; git -C "$C" init -q
cd "$P" || exit 1; git init -q -b main; git config user.email t@t; git config user.name t
mkdir -p changes/archive/2026-01-01-a0-base
# shellcheck disable=SC2016 # literal backticks
printf '| `a0-base` |\n| `s1-api` |\n| `s2-crypto` |\n| `t1-auth` |\n| `w1-site` |\n' > roadmap.md
mk() { mkdir -p "changes/$1"; printf 'schema: spec-driven\n%s\n' "$2" > "changes/$1/.openspec.yaml"; printf "%b" "$3" > "changes/$1/tasks.md"; }
mk s1-api    'x-depends_on: [a0-base]'        '- [x] 1.1 a\n- [ ] 1.2 b\n'
mk s2-crypto 'x-depends_on: [s1-api]'         '- [ ] 1.1 a\n'
mk t1-auth   'x-depends_on: [a0-base, s1-api]' '- [x] 1.1 a\n'
mk w1-site   ''                             '- [ ] 1.1 a\n'
mk k1-api    ''                             '## 1. Contract\n- [x] 1.1 schema\n## 2. Build\n- [ ] 2.1 b\n'
mk k2-ui     'x-depends_on: [k1-api:contract]'  '- [ ] 1.1 a\n'
mk k3-ui     'x-depends_on: [w1-site:contract]' '- [ ] 1.1 a\n'
# shellcheck disable=SC2016 # literal backticks
printf '| # | Change | Usable outcome | Needs |\n| N1 | `n1-new` | x | - |\n| N2 | `n2-later` | x | s2-crypto |\n| N3 | `n3-on-s1` | x | a0-base, s1-api |\n| N4 | `n4-on-contract` | x | k1-api:contract |\n| N5 | `n5-no-contract` | x | w1-site:contract |\n| S1 | `s1-api` | x | - |\n' >> roadmap.md
jq -n '{repos:{plan:"acme/plan",code:["acme/app"]},owner:{login:"boss"},paths:{roadmap:"roadmap.md",changes:"changes/"}}' > crew.json
git add -A; git commit -qm base; git update-ref refs/remotes/origin/main HEAD

run() { env CREW_PLAN_DIR="$P" CREW_CODE_DIR="$C" OFFLINE=1 BLOCKERS="${BLOCKERS:-}" bash "$script" "$@"; }
expect() { got=$(BLOCKERS="${3:-}" run | awk -F'\t' -v id="$1" '$1==id{print $2" "$3}' | sed 's/ $//')
  [ "$got" = "$2" ] && ok "$1 $2" || no "$1 expected '$2', got '$got'"; }

expect s1-api "ready"
expect s2-crypto "blocked needs s1-api"
expect t1-auth "finished"
expect w1-site "ready"
# A :contract dependency is met once the dep's "Contract" task group is ticked; a dep without one blocks.
expect k2-ui "stackable on k1-api"
expect k3-ui "blocked needs w1-site:contract"
# s1's branch has every task ticked: s1 is in review, s2 may stack on it.
git switch -qc claude/change-s1-api; sed -i.bak 's/- \[ \] 1.2/- [x] 1.2/' changes/s1-api/tasks.md; rm -f changes/s1-api/*.bak
git commit -qam tick; git update-ref refs/remotes/origin/claude/change-s1-api HEAD; git switch -q main
expect s1-api "review"
expect s2-crypto "stackable on s1-api"
# s1's branch archives the change inside its PR: still in review, not ready again.
git switch -q claude/change-s1-api; git mv changes/s1-api changes/archive/2026-01-02-s1-api
git commit -qam archive; git update-ref refs/remotes/origin/claude/change-s1-api HEAD; git switch -q main
expect s1-api "review"
expect s2-crypto "stackable on s1-api"
expect w1-site "parked owner #7" "7 owner Need a domain for w1-site landing"
expect w1-site "parked rescue #8" "8 rescue Rescue: w1-site 1.1"
expect w1-site "parked owner #7" "$(printf '8 rescue Rescue: w1-site 1.1\n7 owner Need a domain for w1-site')"
# A needs-owner-only issue (gate) parks the change only when its next unticked task is a Gate: task.
expect w1-site "ready" "9 gate Approve the w1-site cost brief"
expect w1-site "parked rescue #8" "$(printf '9 gate Approve w1-site\n8 rescue Rescue: w1-site 1.1')"
mk g1-gated '' '- [x] 1.1 brief\n- [ ] 1.2 Gate: owner approved the brief\n- [ ] 1.3 apply\n'
expect g1-gated "parked owner #9" "9 gate Approve the g1-gated cost brief"; rm -rf changes/g1-gated
# Ownership: another App's PR on the change branch or its -r<n> rebranch makes the change owned; a similar id does not.
own() { got=$(PR_AUTHORS="$(printf "$2")" AGENT_PERSONA='' run | awk -F'\t' -v id="$1" '$1==id{print $2" "$3}' | sed 's/ $//')
  [ "$got" = "$3" ] && ok "owned: $4" || no "owned: $4: expected '$3', got '$got'"; }
own w1-site 'claude/change-w1-site\tacme-b[bot]' 'owned acme-b[bot]' 'exact head'
own w1-site 'claude/change-w1-site-r2\tacme-b[bot]' 'owned acme-b[bot]' '-r2 rebranch'
own w1-site 'claude/change-w1-site-rework\tacme-b[bot]' 'ready' 'similar id is not the change'
[ "$(BLOCKERS='7 owner w1-site' run --ready | tr '\n' ' ')" = "s2-crypto k1-api k2-ui " ] && ok "--ready lists only takeable changes" || no "--ready"
# Unwritten rows whose Needs are archived or fully ticked on a branch; written rows (s1) never.
[ "$(run --plannable | tr '\n' ' ')" = "n1-new n3-on-s1 n4-on-contract " ] && ok "--plannable lists unwritten rows that can start" || no "--plannable, got '$(run --plannable | tr '\n' ' ')'"
# A code-repo change branch with history unrelated to main is not takeable.
git -C "$C" -c user.email=t@t -c user.name=t commit -q --allow-empty -m main; git -C "$C" update-ref refs/remotes/origin/main HEAD
git -C "$C" update-ref refs/remotes/origin/claude/change-w1-site "$(git -C "$C" -c user.email=t@t -c user.name=t commit-tree -m orphan "$(git -C "$C" mktree </dev/null)")"
expect w1-site "blocked unrelated history on claude/change-w1-site"
# Unmerged ticks on the newest push-pr.sh rebranch (-r<n>) count, not the stale merged branch.
cd "$P" || exit 1; git update-ref refs/remotes/origin/claude/change-k1-api HEAD
git switch -qc claude/change-k1-api-r1; sed -i.bak 's/- \[ \] 2.1/- [x] 2.1/' changes/k1-api/tasks.md; rm -f changes/k1-api/*.bak
GIT_COMMITTER_DATE='2030-01-01T00:00:00Z' git commit -qam tick; git update-ref refs/remotes/origin/claude/change-k1-api-r1 HEAD; git switch -q main
expect k1-api "review"
echo "change-status.test: $pass passed, $failn failed"; [ "$failn" = 0 ]
