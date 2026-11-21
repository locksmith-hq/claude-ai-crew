#!/usr/bin/env bash
# Validates a domain pack: scripts/validate-pack.sh path/to/crew.json
# Checks required keys, that channel roles exist, and that no secret-looking value is in the file.
set -uo pipefail
f="${1:?usage: validate-pack.sh path/to/crew.json}"
command -v jq >/dev/null || { echo "validate-pack: jq is required" >&2; exit 2; }
fail=0; bad() { echo "validate-pack FAIL: $*" >&2; fail=1; }
jq -e . "$f" >/dev/null 2>&1 || { echo "validate-pack FAIL: $f is not valid JSON" >&2; exit 1; }
for k in project owner.login repos.harness repos.plan commands.quick commands.ci roles channels default_worker; do
  jq -e --arg k "$k" 'getpath($k|split(".")) != null' "$f" >/dev/null || bad "missing key: $k"
done
jq -e '(.repos.code|type)=="array" and (.repos.code|length)>0' "$f" >/dev/null || bad "repos.code must be a non-empty list"
# every role named by a channel, default_worker or debate must exist (owner is implicit)
missing=$(jq -r '. as $c | [ ($c.channels[]|(.from//[])[], (.between//[])[], (.escalate_to//empty), (.to//empty), (.on_close//empty), (.on_reply//empty)), $c.default_worker ]
  | map(select(. != null and . != "owner" and . != "raiser")) | unique[] | select(. as $r | $c.roles|has($r)|not)' "$f")
[ -z "$missing" ] || bad "roles used but not defined: $(echo "$missing" | tr '\n' ' ')"
jq -e '[.roles[]|.secret]|all(test("^[A-Z][A-Z0-9_]*$"))' "$f" >/dev/null || bad "roles.*.secret must be an environment variable NAME, never a token"
grep -qE 'sk-ant-|gh[pousr]_[A-Za-z0-9]{20,}' "$f" && bad "a token-looking value is in $f"
[ "$fail" = 0 ] && echo "validate-pack: OK"
exit "$fail"
