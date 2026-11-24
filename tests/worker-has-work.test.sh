#!/usr/bin/env bash
# Tests for scripts/worker-has-work.sh against a stubbed `gh` (fixture JSON per URL, filtered by the script's own -q)
# and a stubbed change-status.sh.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; pass=0; failn=0
ok() { echo "ok   $1"; pass=$((pass+1)); }; no() { echo "FAIL $1"; failn=$((failn+1)); }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
mkdir -p "$t/scripts/lib" "$t/bin" "$t/fx" "$t/plan"
cp "$HERE/../scripts/worker-has-work.sh" "$t/scripts/"; cp "$HERE/../scripts/lib/crew-env.sh" "$t/scripts/lib/"
jq '.repos.plan="acme/plan" | .repos.code=["acme/app"] | .roles["worker-b"]={app: "acme-worker-b", logins: ["acme-old-b[bot]"]}' \
  "$HERE/../examples/domain-pack/crew.json" >"$t/plan/crew.json"
printf '#!/usr/bin/env bash\n' >"$t/scripts/change-status.sh"  # no takeable or plannable changes
cat >"$t/bin/gh" <<'EOF'
#!/usr/bin/env bash
# gh api <url> -q <filter>: the fixture named for the url, through jq
url=$2; q=${4:-.}
case "$url" in
  *hold-workers*) f=hold ;; *needs-rescue*) f=rescue ;; *review-failed*) f=rf ;; *pulls*) f=pulls ;;
  *runs?branch=main*) f=main ;; *runs*) f=red ;; *) exit 1 ;;
esac
jq -r "$q" "$FX/$f.json"
EOF
chmod +x "$t/bin/gh"
echo '[]' >"$t/fx/rf.json"
echo '{"workflow_runs":[{"conclusion":"success"}]}' >"$t/fx/main.json"
echo '{"workflow_runs":[{"conclusion":"failure"}]}' >"$t/fx/red.json"
echo '[{"user":{"login":"x"},"head":{"ref":"claude/change-a1-red"}},
       {"user":{"login":"acme-old-b[bot]"},"head":{"ref":"claude/change-b2-red"}}]' >"$t/fx/pulls.json"
check() { # <name> <hold json> <rescue json> <expected output> <expected exit> [role]
  echo "$2" >"$t/fx/hold.json"; echo "$3" >"$t/fx/rescue.json"
  got=$(cd "$t/plan" && env -i HOME="$t" PATH="$t/bin:$PATH" FX="$t/fx" CREW_PLAN_DIR="$t/plan" CREW_CODE_DIR="$t/plan" \
    AGENT_ID_DIR=/nonexistent bash "$t/scripts/worker-has-work.sh" ${6:+"$6"} 2>/dev/null); code=$?
  if [ "$got" = "$(printf '%b' "$4")" ] && [ "$code" = "$5" ]; then ok "$1"; else no "$1: exit $code, got '$got'"; fi
}
both='work: CI is red on claude/change-a1-red\nwork: CI is red on claude/change-b2-red'
check "red PRs are work" '[]' '[]' "$both" 0
echo '[{"pull_request":{},"user":{"login":"acme-pm[bot]"}}]' >"$t/fx/rf.json"
check "no persona: every review-failed PR counts" '[]' '[]' "work: 1 of your PR(s) failed merge review\n$both" 0
check "persona argument: only its own PRs, old login included" '[]' '[]' 'work: CI is red on claude/change-b2-red' 0 worker-b
echo '[]' >"$t/fx/rf.json"
check "hold-workers blocker: idle despite work" '[{"number":1}]' '[]' 'idle' 1
check "rescued change's red PR skipped" '[]' '[{"title":"Rescue: CI","body":"Change: a1-red\nstuck"}]' 'work: CI is red on claude/change-b2-red' 0
check "every red PR rescued: idle" '[]' '[{"title":"Rescue: a1-red and b2-red","body":""}]' 'idle' 1
# change-status.sh must see the persona argument, or the worker's own change PR reads as owned by another.
printf '#!/usr/bin/env bash\n[ "${1:-}" != --plannable ] && [ "${AGENT_PERSONA:-}" = worker-a ] && printf "c9-x\\tready\\t\\n"; exit 0\n' >"$t/scripts/change-status.sh"
echo '[]' >"$t/fx/pulls.json"
check "persona argument reaches change-status.sh" '[]' '[]' 'work: c9-x is ready' 0 worker-a
echo "worker-has-work.test: $pass passed, $failn failed"; [ "$failn" = 0 ]
