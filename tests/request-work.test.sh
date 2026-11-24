#!/usr/bin/env bash
# Tests for scripts/request-work.sh's dampener against a stubbed `gh` (fixture JSON per URL) and a stubbed ready-depth.sh.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; pass=0; failn=0
ok() { echo "ok   $1"; pass=$((pass+1)); }; no() { echo "FAIL $1"; failn=$((failn+1)); }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
mkdir -p "$t/scripts/lib" "$t/bin" "$t/fx" "$t/plan"
cp "$HERE/../scripts/request-work.sh" "$t/scripts/"; cp "$HERE/../scripts/lib/crew-env.sh" "$t/scripts/lib/"
jq '.repos.plan="acme/plan" | .repos.code=["acme/app"]' "$HERE/../examples/domain-pack/crew.json" >"$t/plan/crew.json"
printf '#!/usr/bin/env bash\ncat "$FX/depth.txt"\n' >"$t/scripts/ready-depth.sh"
cat >"$t/bin/gh" <<'EOF'
#!/usr/bin/env bash
# gh api <url> [-f ...] -q <filter>: a POST (any -f) records its body and prints a URL; reads come from fixtures.
url=$2; shift 2; q=.; post=0
while [ $# -gt 0 ]; do case "$1" in -q) q=$2; shift ;; -f) post=1; [[ "$2" == body=* ]] && printf '%s' "${2#body=}" >"$FX/posted" ;; esac; shift; done
[ "$post" = 1 ] && { echo "https://example/issues/99"; exit 0; }
case "$url" in *state=open*) f=open ;; *state=closed*) f=closed ;; *) exit 1 ;; esac
jq -r "$q" "$FX/$f.json"
EOF
chmod +x "$t/bin/gh"
check() { # <name> <open json> <closed json> <depth> <expected first line of output>
  echo "$2" >"$t/fx/open.json"; echo "$3" >"$t/fx/closed.json"; printf '%s\n' "$4" >"$t/fx/depth.txt"; rm -f "$t/fx/posted"
  got=$(cd "$t/plan" && env -i HOME="$t" PATH="$t/bin:$PATH" FX="$t/fx" CREW_PLAN_DIR="$t/plan" CREW_CODE_DIR="$t/plan" \
    AGENT_ID_DIR=/nonexistent bash "$t/scripts/request-work.sh" worker-a 2>&1 | head -1)
  [ "$got" = "$5" ] && ok "$1" || no "$1: got '$got'"
}
d0='depth=0 target=4 evergreen=0 LOW
blocked: a1-x parked rescue #3'
asked() { printf '<!-- agent -->\n```ready-depth\n%s\n```\n' "$1" | jq -Rs '[{body: .}]'; }
check "an open ask is not repeated" '[1]' '[]' "$d0" "needs-work: already open"
check "no recent answer: ask" '[]' '[]' "$d0" "https://example/issues/99"
grep -q '^- Lead: ' "$t/fx/posted" && grep -q "^$(head -1 <<<"$d0")\$" "$t/fx/posted" && ok "the ask has a Lead question and the depth block" || no "ask body"
check "answered, nothing changed since: no new ask" '[]' "$(asked "$d0")" "$d0" "needs-work: answered within 6h and nothing changed since; not asking again"
check "answered, a change was claimed since: still no new ask" '[]' "$(asked "$d0")" "$d0
blocked: b2-y claimed worker-b-1" "needs-work: answered within 6h and nothing changed since; not asking again"
check "answered, something new blocked since: ask again" '[]' "$(asked "$d0")" "$d0
blocked: b2-y blocked unrelated history on claude/change-b2-y" "https://example/issues/99"
check "answer without a depth block (older format): ask" '[]' '[{"body":"old"}]' "$d0" "https://example/issues/99"
echo "request-work.test: $pass passed, $failn failed"; [ "$failn" = 0 ]
