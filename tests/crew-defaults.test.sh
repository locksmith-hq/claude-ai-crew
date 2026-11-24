#!/usr/bin/env bash
# The org crew.json holds overrides only: crew-env.sh merges it over crew.defaults.json.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; LIB="$HERE/../scripts/lib/crew-env.sh"; pass=0; failn=0
ok() { echo "ok   $1"; pass=$((pass+1)); }; no() { echo "FAIL $1"; failn=$((failn+1)); }
W=$(mktemp -d); mkdir -p "$W/plan"
cat >"$W/plan/crew.json" <<'JSON'
{"project": "acme", "owner": {"login": "boss"}, "repos": {"plan": "acme/plan", "code": ["acme/app"]},
 "roles": {"lead": {"name": "Iron Man"}, "worker-b": {"batched": true}},
 "channels": {"debate": {"turns": 5}, "needs-work": {"to": ["pm", "lead"]}}}
JSON
q() { env -i HOME="$W" PATH="$PATH" CREW_PLAN_DIR="$W/plan" Q="$1" bash -c ". '$LIB'; jq -c \"\$Q\" \"\$CREW_CONFIG\""; }
[ "$(q '.roles.lead')" = '{"batched":true,"name":"Iron Man"}' ] && ok "role fields merge" || no "role fields merge: $(q '.roles.lead')"
[ "$(q '.roles["worker-b"].batched')" = true ] && ok "org overrides a default" || no "org overrides a default"
[ "$(q '.roles["worker-c"] != null and .channels["harness-blocker"].to == "owner"')" = true ] && ok "defaults fill the rest" || no "defaults fill the rest"
[ "$(q '.channels.debate')" = '{"between":["pm","lead"],"turns":5,"escalate_to":"lead"}' ] && ok "objects merge, scalar overridden" || no "debate: $(q '.channels.debate')"
[ "$(q '.channels["needs-work"].to')" = '["pm","lead"]' ] && ok "arrays and scalars replaced" || no "needs-work.to"
out=$(env -i HOME="$W" PATH="$PATH" CREW_PLAN_DIR="$W/plan" bash -c ". '$LIB'; echo \"\$PLAN_REPO \$CODE_REPO \$(basename \$CREW_PLAN_DIR)\"")
[ "$out" = "acme/plan acme/app plan" ] && ok "required fields and plan dir from the org file" || no "required fields: $out"
echo '{"project":"x","repos":{"plan":"a/p"}}' >"$W/plan/crew.json"
env -i HOME="$W" PATH="$PATH" CREW_PLAN_DIR="$W/plan" bash -c ". '$LIB'" >/dev/null 2>&1 && no "repos.code[0] still required" || ok "repos.code[0] still required"
rm -rf "$W"; echo "crew-defaults.test: $pass passed, $failn failed"; [ "$failn" = 0 ]
