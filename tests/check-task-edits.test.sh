#!/usr/bin/env bash
# Tests for scripts/check-task-edits.sh in a throwaway plan repo (offline). Protected paths come from crew.json.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; guard="$HERE/../scripts/check-task-edits.sh"; pass=0; failn=0
ok() { echo "ok   $1"; pass=$((pass+1)); }; no() { echo "FAIL $1"; failn=$((failn+1)); }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT; P="$W/plan"; mkdir -p "$P"; cd "$P" || exit 1
git init -q -b main; git config user.email t@t; git config user.name t
cat > crew.json <<'J'
{"project":"t","repos":{"plan":"acme/plan","code":["acme/app"]},"owner":{"login":"boss"},
 "paths":{"changes":"changes/","owner_rules":"owner.md","decisions":"decisions.md"},
 "trust_root":[".github/workflows/","crew.json","owner.md","prompts/merge.md","skills/merge-review"],
 "agent_system":["prompts/","skills/","scripts/"]}
J
mkdir -p changes/c1; printf -- '- [ ] 1.1 Do A\n- [ ] 1.2 Do B\n' > changes/c1/tasks.md
git add -A; git commit -qm base; git update-ref refs/remotes/origin/main HEAD
git switch -qc claude/change-c1

expect() { if BRANCH="$2" CREW_PLAN_DIR="$P" bash "$guard" >/dev/null 2>&1; then got=0; else got=1; fi
  [ "$got" = "$1" ] && ok "$3" || no "$3 (expected exit $1, got $got)"; }

sed -i.bak 's/- \[ \] 1.1/- [x] 1.1/' changes/c1/tasks.md; rm -f changes/c1/*.bak; expect 0 claude/change-c1 "tick only"
sed -i.bak 's/Do B/Do nothing/' changes/c1/tasks.md; rm -f changes/c1/*.bak;      expect 1 claude/change-c1 "text edit"
expect 0 claude/planning-x "planning branch skips"
git checkout -q -- changes/c1/tasks.md
mkdir -p changes/c2; printf -- '- [ ] 1.1 New\n' > changes/c2/tasks.md
git add -A; expect 0 claude/change-c1 "new change file"
git checkout -q main; printf '# log\n## e1\n' > changes/c1/progress.md; git add -A; git commit -qm log
git update-ref refs/remotes/origin/main HEAD; git switch -qc claude/change-c1b
printf '## e2\n' >> changes/c1/progress.md; expect 0 claude/change-c1b "progress append"
printf '# log\n## edited\n## e2\n' > changes/c1/progress.md; expect 1 claude/change-c1b "progress rewrite"
git checkout -q -- changes/c1/progress.md
mkdir -p prompts; echo x > prompts/worker.md; git add -A
expect 1 claude/change-c1b "agent edits its own prompts"
expect 1 claude/planning-y "planning branch edits agent prompts"
expect 1 owner/some-fix "owner session outside the release edits agent prompts"
expect 1 claude/lead-z "lead branch outside the release edits agent prompts"
expect 0 owner/harness-release-2026-47 "owner weekly release edits agent prompts"
expect 0 claude/harness-release-2026-47 "agent weekly release edits agent prompts"
expect 0 claude/hotfix-red-main "hotfix branch edits agent prompts"
echo x > prompts/merge.md; git add -A
expect 1 claude/harness-release-2026-47 "agent release may not edit a trust-root prompt"
expect 0 owner/harness-release-2026-47 "owner release may edit a trust-root prompt"
git rm -q --cached prompts/merge.md; rm prompts/merge.md
mkdir -p skills/run-start skills/merge-review; echo x > skills/run-start/SKILL.md; git add -A
expect 0 claude/harness-release-2026-47 "agent release may edit a skill"
expect 1 claude/change-c1b "worker branch may not edit a skill"
echo x > skills/merge-review/SKILL.md; git add -A
expect 1 claude/harness-release-2026-47 "agent release may not edit a trust-root skill"
git rm -rq --cached skills prompts; rm -rf skills prompts
mkdir -p .github/workflows; echo x > .github/workflows/ci.yml; git add -A
expect 1 claude/hotfix-x "agent hotfix may not edit workflows"
expect 0 owner/hotfix-x "owner hotfix may edit workflows"
git rm -rq --cached .github; rm -rf .github
git checkout -q main; printf -- '- d1\n' > owner.md; printf -- '- m1\n' > decisions.md; git add -A; git commit -qm owner; git update-ref refs/remotes/origin/main HEAD
git switch -qc claude/change-o1; printf -- '- d2\n' >> owner.md; git add -A
expect 0 claude/change-o1 "agent may append to the owner rules (though listed in trust_root)"
printf -- '- changed\n- d2\n' > owner.md; git add -A
expect 1 claude/change-o1 "agent may not rewrite the owner rules"
printf -- '- d1\n' > owner.md; printf -- '- m2\n' > decisions.md; git add -A
expect 1 claude/change-o1 "agent may not rewrite the decisions file"
git checkout -q -f main; git update-ref refs/remotes/origin/main HEAD; git switch -qc claude/change-c1c
mkdir -p changes/archive; git mv changes/c1 changes/archive/2026-01-01-c1
sed -i.bak 's/- \[ \]/- [x]/' changes/archive/2026-01-01-c1/tasks.md; rm -f changes/archive/2026-01-01-c1/*.bak
printf '## e3\n' >> changes/archive/2026-01-01-c1/progress.md; git add -A
expect 0 claude/change-c1c "archive in the finishing PR (ticks and append only)"
sed -i.bak 's/Do B/Do nothing/' changes/archive/2026-01-01-c1/tasks.md; rm -f changes/archive/2026-01-01-c1/*.bak; git add -A
expect 1 claude/change-c1c "archive copy with edited task text"
git rm -rqf changes/archive
expect 1 claude/change-c1c "change deleted without archive"
# The lists come from the base crew.json: a branch cannot empty them in its own PR to unprotect files.
git checkout -q -f main; git switch -qc claude/change-c1d; jq 'del(.trust_root,.agent_system)' crew.json > c.tmp && mv c.tmp crew.json
mkdir -p prompts; echo x > prompts/worker.md; git add -A
expect 1 claude/change-c1d "branch cannot unprotect files by editing crew.json"
echo "check-task-edits.test: $pass passed, $failn failed"; [ "$failn" = 0 ]
