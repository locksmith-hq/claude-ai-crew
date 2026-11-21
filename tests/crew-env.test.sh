#!/usr/bin/env bash
# Tests for scripts/lib/crew-env.sh using throwaway git repos.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; LIB="$HERE/../scripts/lib/crew-env.sh"; pass=0; failn=0
ok() { echo "ok   $1"; pass=$((pass+1)); }; no() { echo "FAIL $1"; failn=$((failn+1)); }
W=$(mktemp -d); mkdir -p "$W/plan" "$W/code"
git -C "$W/plan" init -q; git -C "$W/plan" remote add origin https://github.com/acme/plan.git
git -C "$W/code" init -q; git -C "$W/code" remote add origin git@github.com:acme/app.git
jq '.repos.plan="acme/plan" | .repos.code=["acme/app"] | .owner.login="boss"' "$HERE/../examples/domain-pack/crew.json" > "$W/plan/crew.json"
out=$(cd "$W/plan" && env -i HOME="$W" PATH="$PATH" CREW_WORKSPACE="$W" bash -c ". '$LIB'; echo \"\$PLAN_REPO \$CODE_REPO \$OWNER_LOGIN \$(basename \$CREW_PLAN_DIR) \$(basename \$CREW_CODE_DIR) \$QUICK_CHECK\"")
[ "$out" = "acme/plan acme/app boss plan code make quick" ] && ok "resolves repos, dirs and commands" || no "resolves repos, dirs and commands: $out"
out=$(cd "$W" && env -i HOME="$W" PATH="$PATH" CREW_PLAN_DIR="$W/plan" CREW_WORKSPACE="$W" bash -c ". '$LIB'; crew_role_login lead; crew_get '.owner.login'")
[ "$out" = "$(printf 'example-lead[bot]\nboss')" ] && ok "role login and crew_get" || no "role login and crew_get: $out"
env -i HOME="$W" PATH="$PATH" bash -c "cd /; . '$LIB'" >/dev/null 2>&1 && no "missing config fails" || ok "missing config fails"
echo '{"repos":{}}' > "$W/bad.json"; env -i HOME="$W" PATH="$PATH" CREW_CONFIG="$W/bad.json" bash -c ". '$LIB'" >/dev/null 2>&1 && no "incomplete config fails" || ok "incomplete config fails"
rm -rf "$W"; echo "crew-env.test: $pass passed, $failn failed"; [ "$failn" = 0 ]
