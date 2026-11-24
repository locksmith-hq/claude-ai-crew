#!/usr/bin/env bash
# Tests for scripts/route.sh: its built-in selftest, plus checks that it reads a real crew.json (the example pack).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; R="$HERE/../scripts/route.sh"; pass=0; failn=0
ok() { echo "ok   $1"; pass=$((pass+1)); }; no() { echo "FAIL $1"; failn=$((failn+1)); }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
CFG="$HERE/../examples/domain-pack/crew.json"
run() { env -i HOME="$W" PATH="$PATH" CREW_CONFIG="$CFG" CREW_PLAN_DIR="$W" CREW_CODE_DIR="$W" "$@"; }  # no network: gh is never reached below

bash "$R" selftest >"$W/self.out" 2>&1 && ok "route.sh selftest" || { no "route.sh selftest"; grep -v '^ok' "$W/self.out"; }

ev() { # <expected> <event-name> <event-json>
  printf '%s' "$3" >"$W/ev.json"
  got=$(run GITHUB_EVENT_NAME="$2" bash "$R" event "$W/ev.json" 2>&1)
  [ "$got" = "$(printf '%b' "$1")" ] && ok "$2 -> ${1:-nothing}" || no "$2: want '$1' got '$got'"
}
# the example pack: project "example", owner and roles from crew.json
OWN=$(jq -r .owner.login "$CFG")
ev 'lead\tneeds-rescue #5 opened' issues '{"action":"labeled","label":{"name":"needs-rescue"},"issue":{"number":5,"labels":[{"name":"needs-rescue"}]}}'
ev 'lead\towner replied on needs-owner #7' issue_comment '{"issue":{"number":7,"labels":[{"name":"needs-owner"}]},"comment":{"user":{"login":"'"$OWN"'"},"body":"ok"}}'
ev 'lead\towner tagged you on #7: u' issue_comment '{"issue":{"number":7,"labels":[]},"comment":{"html_url":"u","user":{"login":"'"$OWN"'"},"body":"@example-lead look"}}'
ev '' issue_comment '{"issue":{"number":7,"labels":[]},"comment":{"user":{"login":"stranger"},"body":"@example-lead look"}}'
ev 'lead\tCI failed on main' workflow_run '{"workflow_run":{"name":"ci","conclusion":"failure","head_branch":"main","event":"push","pull_requests":[]}}'

# a channel's `to` may list several roles: one wake line each (needs-work wakes the PM and the lead)
jq '.channels["needs-work"].to = ["pm", "lead", "pm"]' "$CFG" >"$W/multi.json"
CFG="$W/multi.json" ev 'pm\tneeds-work #16 opened\nlead\tneeds-work #16 opened' issues '{"action":"labeled","label":{"name":"needs-work"},"issue":{"number":16,"labels":[{"name":"needs-work"}]}}'
ev 'pm\tneeds-work #16 opened' issues '{"action":"labeled","label":{"name":"needs-work"},"issue":{"number":16,"labels":[{"name":"needs-work"}]}}'
bash "$HERE/../scripts/validate-pack.sh" "$W/multi.json" >/dev/null && ok "validate-pack accepts a list of roles in to" || no "validate-pack list to"
jq '.channels["needs-work"].to = ["pm", "ghost"]' "$CFG" >"$W/ghost.json"
bash "$HERE/../scripts/validate-pack.sh" "$W/ghost.json" >/dev/null 2>&1 && no "validate-pack undefined role in a to list" || ok "validate-pack rejects an undefined role in a to list"

# fire without a token: warns and exits 0 instead of calling the network
out=$(run bash "$R" fire lead "test" 2>&1); rc=$?
[ "$rc" = 0 ] && grep -q 'no routine trigger or' <<<"$out" && ok "fire without token warns" || no "fire without token warns: rc=$rc $out"
run bash "$R" >/dev/null 2>&1; [ "$?" = 2 ] && ok "no argument prints usage, exit 2" || no "usage exit code"

echo "route.test: $pass passed, $failn failed"; [ "$failn" = 0 ]
