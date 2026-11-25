#!/usr/bin/env bash
# Tests for scripts/resume-card.sh: a plan repo with a bare origin (ticks on a -r branch), a stubbed `gh` (fixture
# JSON per URL, filtered by the script's own -q), and stubbed change-status.sh and ci-failures.sh.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; pass=0; failn=0
ok() { echo "ok   $1"; pass=$((pass+1)); }; no() { echo "FAIL $1"; failn=$((failn+1)); }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
mkdir -p "$t/scripts/lib" "$t/bin" "$t/fx"
cp "$HERE/../scripts/resume-card.sh" "$t/scripts/"; cp "$HERE/../scripts/lib/crew-env.sh" "$t/scripts/lib/"
printf '#!/usr/bin/env bash\nprintf "c1-x\\tready\\t\\n"\n' >"$t/scripts/change-status.sh"
printf '#!/usr/bin/env bash\n[ "${2:-}" = -R ] && echo "FAIL decide (failure) billing: spending limit" || echo green\n' >"$t/scripts/ci-failures.sh"

# Plan repo: main has every task open; the newer -r2 branch ticked 1.1.
git init -q --bare "$t/origin.git"; git init -q -b main "$t/plan"
g() { git -C "$t/plan" -c user.name=t -c user.email=t@example.com "$@"; }
jq '.repos.plan="acme/plan" | .repos.code=["acme/app"] | .roles["worker-a"]={app: "acme-worker-a"}' \
  "$HERE/../examples/domain-pack/crew.json" >"$t/plan/crew.json"
mkdir -p "$t/plan/changes/c1-x"
printf '## 1. Contract\n- [ ] 1.1 first\n- [ ] 1.2 second\n## 2. Build\n- [ ] 2.1 third\n' >"$t/plan/changes/c1-x/tasks.md"
printf '## 2026-11-01 worker\n- old entry\n## 2026-11-02 worker\n- Notes for next session: start at 1.2\n' >"$t/plan/changes/c1-x/progress.md"
g add -A; g commit -qm init; g remote add origin "$t/origin.git"; g push -q origin main
g checkout -qb claude/change-c1-x-r2; sed -i.bak 's/- \[ \] 1.1/- [x] 1.1/' "$t/plan/changes/c1-x/tasks.md"; rm "$t/plan/changes/c1-x/tasks.md.bak"
g commit -qam tick; g push -q origin claude/change-c1-x-r2; g checkout -q main

cat >"$t/bin/gh" <<'EOF'
#!/usr/bin/env bash
url=$2; q=${4:-.}
case "$url" in */app/pulls*) f=code ;; */plan/pulls*) f=plan ;; */comments*) f=comments ;; *) exit 1 ;; esac
jq -r "$q" "$FX/$f.json"
EOF
chmod +x "$t/bin/gh"
long=$(printf 'x%.0s' $(seq 1 900))
echo '[{"number":7,"head":{"ref":"claude/change-c1-x-r2"},"user":{"login":"acme-worker-b[bot]"},"auto_merge":null},
       {"number":8,"head":{"ref":"claude/change-c1-xy"},"user":{"login":"acme-worker-a[bot]"},"auto_merge":null}]' >"$t/fx/code.json"
echo '[{"number":3,"head":{"ref":"claude/change-c1-x"},"user":{"login":"acme-worker-a[bot]"},"auto_merge":null}]' >"$t/fx/plan.json"
jq -n --arg l "$long" '[{"body":"<!-- agent --> merge-review abc1234: PASS"},{"body":("<!-- agent --> merge-review def5678: FAIL\nBlocking: " + $l)}]' >"$t/fx/comments.json"

out=$(cd "$t/plan" && env -i HOME="$t" PATH="$t/bin:$PATH" FX="$t/fx" CREW_PLAN_DIR="$t/plan" CREW_CODE_DIR="$t/plan" \
  AGENT_ID_DIR=/nonexistent AGENT_PERSONA=worker-a bash "$t/scripts/resume-card.sh" c1-x 2>&1); code=$?
has() { grep -qF -- "$2" <<<"$out" && ok "$1" || no "$1: missing '$2' in: $out"; }
hasnt() { grep -qF -- "$2" <<<"$out" && no "$1: unexpected '$2'" || ok "$1"; }
[ "$code" = 0 ] && ok "exit 0" || no "exit $code"
has "state from change-status" "state: ready"
has "ticks read from the newest -r branch" "tasks: 1 done, 2 open (from origin/claude/change-c1-x-r2)"
hasnt "ticked task not listed as open" "1.1 first"
has "open task under its heading" "## 1. Contract"
has "last progress entry only" "Notes for next session: start at 1.2"
hasnt "older progress entries dropped" "old entry"
has "another worker's PR flagged" "code PR #7 claude/change-c1-x-r2 by acme-worker-b[bot] (NOT YOURS)"
hasnt "a different change with the same prefix ignored" "#8"
has "newest merge-review FAIL shown" "merge-review def5678: FAIL"
hasnt "older verdict not shown" "abc1234"
[ "$(awk 'length > 300' <<<"$out" | wc -l | tr -d ' ')" = 0 ] && ok "long comment lines truncated" || no "a line over 300 chars"
has "plan PR CI failure (billing) shown" "billing: spending limit"
echo "resume-card.test: $pass passed, $failn failed"; [ "$failn" = 0 ]
