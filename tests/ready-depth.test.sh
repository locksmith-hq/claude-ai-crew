#!/usr/bin/env bash
# Self-test for scripts/ready-depth.sh: a throwaway plan repo and code repo, no network (OFFLINE=1, issues in BLOCKERS).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; script="$HERE/../scripts/ready-depth.sh"; pass=0; failn=0
ok() { echo "ok   $1"; pass=$((pass+1)); }; no() { echo "FAIL $1"; failn=$((failn+1)); }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT; P="$W/plan"; C="$W/code"; mkdir -p "$P" "$C"
cd "$P" || exit 1; git init -q -b main; git config user.email t@t; git config user.name t
mk() { mkdir -p "changes/$1"; printf 'schema: spec-driven\n%s\n' "$2" > "changes/$1/.openspec.yaml"; printf "%b" "$3" > "changes/$1/tasks.md"; }
mk s1-api   ''                       '- [ ] 1.1 a\n'
mk s2-ui    'x-depends_on: [s1-api]' '- [ ] 1.1 a\n'
mk s3-gated ''                       '- [ ] 1.1 Gate: owner approves\n'
mk s4-done  ''                       '- [x] 1.1 a\n'
mk s5-orph  ''                       '- [ ] 1.1 a\n'
mk r1-lint  'x-evergreen: true'      '- [ ] 1.1 a\n'
touch roadmap.md
jq -n '{repos:{plan:"acme/plan",code:["acme/app"]},paths:{roadmap:"roadmap.md",changes:"changes/"},dispatch:{workers:["worker-a","worker-b"]},roles:{"worker-a":{},"worker-b":{},"worker-c":{}}}' > crew.json
git add -A; git commit -qm base
# s5-orph's code branch shares no history with main.
git -C "$C" init -q; git -C "$C" -c user.email=t@t -c user.name=t commit -q --allow-empty -m main; git -C "$C" update-ref refs/remotes/origin/main HEAD
git -C "$C" update-ref refs/remotes/origin/claude/change-s5-orph "$(git -C "$C" -c user.email=t@t -c user.name=t commit-tree -m orphan "$(git -C "$C" mktree </dev/null)")"

run() { env CREW_PLAN_DIR="$P" CREW_CODE_DIR="$C" OFFLINE=1 BLOCKERS="9 gate s3-gated cost brief" bash "$script"; }
check() { [ "$(run)" = "$(printf '%b' "$2")" ] && ok "$1" || no "$1: got '$(run)'"; }

blocked='blocked: s2-ui blocked needs s1-api\nblocked: s3-gated parked owner #9\nblocked: s5-orph blocked unrelated history on claude/change-s5-orph'
check "target is dispatch.workers + 1; one evergreen is LOW" "depth=2 target=3 evergreen=1 LOW\n$blocked"
mk r2-deps 'x-evergreen: true' '- [ ] 1.1 a\n'
check "depth and two evergreen changes meet the target" "depth=3 target=3 evergreen=2 ok\n$blocked"
jq 'del(.dispatch)' crew.json > c.tmp && mv c.tmp crew.json
check "no dispatch: the worker roles count" "depth=3 target=4 evergreen=2 LOW\n$blocked"
echo "ready-depth.test: $pass passed, $failn failed"; [ "$failn" = 0 ]
