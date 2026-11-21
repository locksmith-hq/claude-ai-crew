#!/usr/bin/env bash
# Tests for scripts/lib/claude_token.py with a fake `claude` and a stub `gh` (no network, no real token).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; TOK="$HERE/../scripts/lib/claude_token.py"; pass=0; failn=0
ok() { echo "ok   $1"; pass=$((pass+1)); }; no() { echo "FAIL $1"; failn=$((failn+1)); }
command -v python3 >/dev/null || { echo "claude-token.test: python3 missing, skipped"; exit 0; }
S=$(mktemp -d); mkdir -p "$S/bin"; LOG="$S/gh.log"; SEEN="$S/seen"; : > "$LOG"
FAKE="sk-ant-oat01-$(printf 'A%.0s' $(seq 1 40))"
cat > "$S/claude-ok" <<EOS
#!/usr/bin/env bash
echo "Welcome to the fake Claude"; echo "Your OAuth token (valid for 1 year):"; echo "$FAKE"; echo "Store this token securely."
EOS
cat > "$S/claude-fail" <<'EOS'
#!/usr/bin/env bash
echo "login cancelled"; exit 1
EOS
cat > "$S/claude-none" <<'EOS'
#!/usr/bin/env bash
echo "done, but no token printed"
EOS
# a token wrapped across lines by the terminal, with the URL junk the real tool printed after it
cat > "$S/claude-wrap" <<EOS
#!/usr/bin/env bash
echo "Your OAuth token (valid for 1 year):"; echo ""
echo "\${FAKE:0:60}"; echo "\${FAKE:60}"; echo ""; echo "Store this token securely."
EOS
sed -i.bak "s|\\\${FAKE:0:60}|${FAKE:0:30}|; s|\\\${FAKE:60}|${FAKE:30}|" "$S/claude-wrap"; rm -f "$S/claude-wrap.bak"
chmod +x "$S"/claude-*
cat > "$S/bin/gh" <<GH
#!/usr/bin/env bash
echo "\$*" >> "$LOG"
[ "\$1 \$2" = "secret set" ] && cat >> "$SEEN"
exit 0
GH
chmod +x "$S/bin/gh"; export PATH="$S/bin:$PATH"
out=$(env -u CLAUDE_CODE_OAUTH_TOKEN -u ANTHROPIC_API_KEY CREW_CLAUDE_CMD="$S/claude-ok" python3 "$TOK" --repos acme/plan,acme/app 2>&1 </dev/null); rc=$?
[ "$rc" = 0 ] && ok "stores the token and exits 0" || no "stores the token and exits 0 (rc=$rc): $out"
grep -q 'secret set CLAUDE_CODE_OAUTH_TOKEN -R acme/plan' "$LOG" && grep -q 'secret set CLAUDE_CODE_OAUTH_TOKEN -R acme/app' "$LOG" && ok "sets the secret in every repo" || no "sets the secret in every repo"
[ "$(grep -o "$FAKE" "$SEEN" | wc -l | tr -d " ")" = 2 ] && ok "token reached gh through stdin, once per repo" || no "token reached gh through stdin"
if grep -q "$FAKE" <<<"$out" || grep -q "$FAKE" "$LOG"; then no "token never shown or passed as an argument"; else ok "token never shown or passed as an argument"; fi
grep -q "token hidden" <<<"$out" && grep -q "Welcome to the fake Claude" <<<"$out" && ok "other output is shown, token masked" || no "other output is shown, token masked"
: > "$SEEN"; out=$(env -u CLAUDE_CODE_OAUTH_TOKEN -u ANTHROPIC_API_KEY CREW_CLAUDE_CMD="$S/claude-fail" python3 "$TOK" --repos acme/plan 2>&1 </dev/null); rc=$?
[ "$rc" != 0 ] && [ ! -s "$SEEN" ] && ok "a failed login stores nothing" || no "a failed login stores nothing"
grep -q "gh secret set" <<<"$out" && ok "a failure explains the manual fallback" || no "a failure explains the manual fallback"
out=$(env -u CLAUDE_CODE_OAUTH_TOKEN -u ANTHROPIC_API_KEY CREW_CLAUDE_CMD="$S/claude-none" python3 "$TOK" --repos acme/plan 2>&1 </dev/null); rc=$?
[ "$rc" != 0 ] && [ ! -s "$SEEN" ] && ok "no token in the output stores nothing" || no "no token in the output stores nothing"
# wrapped token: no 10-character piece of it may be shown, and it is still stored
: > "$SEEN"; out=$(env -u CLAUDE_CODE_OAUTH_TOKEN -u ANTHROPIC_API_KEY CREW_CLAUDE_CMD="$S/claude-wrap" python3 "$TOK" --repos acme/plan 2>&1 </dev/null); rc=$?
leak=0; for i in 0 10 20 30; do piece="${FAKE:$((i+15)):10}"; grep -q "$piece" <<<"$out" && leak=1; done
[ "$leak" = 0 ] && ok "a wrapped token is not shown, even in pieces" || no "a wrapped token is not shown, even in pieces"
[ "$rc" = 0 ] && grep -q "$FAKE" "$SEEN" && ok "a wrapped token is still captured and stored" || no "a wrapped token is still captured and stored (rc=$rc)"
grep -q "Store this token securely" <<<"$out" && ok "output after the token is shown again" || no "output after the token is shown again"
# non-web sources: nothing starts a browser login
: > "$SEEN"; : > "$LOG"
out=$(env -u ANTHROPIC_API_KEY CLAUDE_CODE_OAUTH_TOKEN="$FAKE" CREW_CLAUDE_CMD="$S/claude-fail" python3 "$TOK" --repos acme/plan 2>&1 </dev/null); rc=$?
[ "$rc" = 0 ] && grep -q "secret set CLAUDE_CODE_OAUTH_TOKEN -R acme/plan" "$LOG" && grep -q "$FAKE" "$SEEN" && ok "an env token is stored without any login" || no "an env token is stored without any login (rc=$rc): $out"
grep -q "$FAKE" <<<"$out" && no "the env token is never printed" || ok "the env token is never printed"
: > "$SEEN"; : > "$LOG"
out=$(env -u CLAUDE_CODE_OAUTH_TOKEN ANTHROPIC_API_KEY="sk-ant-api03-$(printf 'B%.0s' $(seq 1 40))" CREW_CLAUDE_CMD="$S/claude-fail" python3 "$TOK" --repos acme/plan 2>&1 </dev/null); rc=$?
[ "$rc" = 0 ] && grep -q "secret set ANTHROPIC_API_KEY -R acme/plan" "$LOG" && ok "an API key in the env is stored as ANTHROPIC_API_KEY" || no "an API key in the env is stored (rc=$rc): $out"
out=$(env -u CLAUDE_CODE_OAUTH_TOKEN -u ANTHROPIC_API_KEY CREW_CLAUDE_CMD="$S/claude-ok" python3 "$TOK" --repos acme/plan --no-web 2>&1 </dev/null); rc=$?
[ "$rc" != 0 ] && grep -q -- "--no-web" <<<"$out" && ok "--no-web fails instead of opening a login" || no "--no-web fails instead of opening a login"
rm -rf "$S"; echo "claude-token.test: $pass passed, $failn failed"; [ "$failn" = 0 ]
