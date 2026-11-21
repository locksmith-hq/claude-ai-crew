#!/usr/bin/env bash
# Tests for leak-check.sh and validate-pack.sh: clean tree passes; each planted defect fails.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; pass=0; failn=0
ok() { echo "ok   $1"; pass=$((pass+1)); }; no() { echo "FAIL $1"; failn=$((failn+1)); }
run() { ROOT="$1" NO_GIT=1 bash "$HERE/leak-check.sh" >/dev/null 2>&1; }
S=$(mktemp -d); echo "hello" > "$S/a.md"
if run "$S"; then ok "clean tree passes"; else no "clean tree passes"; fi
echo "key sk-ant-oat01-abcdefghijklmnop" > "$S/b.md"; if run "$S"; then no "anthropic token fails"; else ok "anthropic token fails"; fi; rm "$S/b.md"
echo "id trig_01ABCDEFGHJKMNPQRSTUVWXYZ0" > "$S/b.md"; if run "$S"; then no "real trigger id fails"; else ok "real trigger id fails"; fi; rm "$S/b.md"
echo "trig_REPLACE_ME" > "$S/b.md"; if run "$S"; then ok "placeholder trigger passes"; else no "placeholder trigger passes"; fi; rm "$S/b.md"
echo "https://d-0123456789.awsapps.com/start" > "$S/b.md"; if run "$S"; then no "SSO URL fails"; else ok "SSO URL fails"; fi; rm "$S/b.md"
printf 'secretword\n' > "$S/.leak-denylist.local"; echo "a secretword here" > "$S/b.md"
if run "$S"; then no "local denylist fails"; else ok "local denylist fails"; fi; rm -rf "$S"
P="$HERE/../examples/domain-pack/crew.json"
if bash "$HERE/validate-pack.sh" "$P" >/dev/null 2>&1; then ok "example pack validates"; else no "example pack validates"; fi
T=$(mktemp); jq 'del(.commands.quick)' "$P" > "$T"; if bash "$HERE/validate-pack.sh" "$T" >/dev/null 2>&1; then no "missing key fails"; else ok "missing key fails"; fi
jq '.channels["needs-rescue"].to="ghost"' "$P" > "$T"; if bash "$HERE/validate-pack.sh" "$T" >/dev/null 2>&1; then no "undefined role fails"; else ok "undefined role fails"; fi
jq '.roles.lead.secret="sk-ant-oat01-abcdefghij"' "$P" > "$T"; if bash "$HERE/validate-pack.sh" "$T" >/dev/null 2>&1; then no "token in secret field fails"; else ok "token in secret field fails"; fi; rm -f "$T"
echo "leak-check.test: $pass passed, $failn failed"; [ "$failn" = 0 ]
