#!/usr/bin/env bash
# Tests for scripts/lib/claude_token.py with a fake `claude` and a stub `gh` (no network, no real token).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; TOK="$HERE/../scripts/lib/claude_token.py"; pass=0; failn=0
ok() { echo "ok   $1"; pass=$((pass+1)); }; no() { echo "FAIL $1"; failn=$((failn+1)); }
command -v python3 >/dev/null || { echo "claude-token.test: python3 missing, skipped"; exit 0; }
S=$(mktemp -d); mkdir -p "$S/bin"; LOG="$S/gh.log"; SEEN="$S/seen"; : > "$LOG"
FAKE="sk-ant-oat01-$(printf 'A%.0s' $(seq 1 95))"
export CREW_VERIFY_CMD=true   # the real check runs `claude -p`; tests use a stub
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
chmod +x "$S"/claude-*
cat > "$S/bin/gh" <<GH
#!/usr/bin/env bash
echo "\$*" >> "$LOG"
[ "\$1 \$2" = "secret set" ] && cat >> "$SEEN"
[ "\$1 \$2" = "secret list" ] && [ -n "\${STUB_HAVE_SECRET:-}" ] && echo "\$STUB_HAVE_SECRET"
exit 0
GH
chmod +x "$S/bin/gh"; export PATH="$S/bin:$PATH"
out=$(env -u CLAUDE_CODE_OAUTH_TOKEN -u ANTHROPIC_API_KEY CREW_CLAUDE_CMD="$S/claude-ok" python3 "$TOK" --repos acme/plan,acme/app 2>&1 </dev/null); rc=$?
[ "$rc" = 0 ] && ok "stores the token and exits 0" || no "stores the token and exits 0 (rc=$rc): $out"
grep -q 'secret set CLAUDE_CODE_OAUTH_TOKEN -R acme/plan' "$LOG" && grep -q 'secret set CLAUDE_CODE_OAUTH_TOKEN -R acme/app' "$LOG" && ok "sets the secret in every repo" || no "sets the secret in every repo"
[ "$(grep -o "$FAKE" "$SEEN" | wc -l | tr -d " ")" = 2 ] && ok "token reached gh through stdin, once per repo" || no "token reached gh through stdin"
if grep -q "$FAKE" <<<"$out" || grep -q "$FAKE" "$LOG"; then no "token never shown or passed as an argument"; else ok "token never shown or passed as an argument"; fi
: > "$SEEN"; out=$(env -u CLAUDE_CODE_OAUTH_TOKEN -u ANTHROPIC_API_KEY CREW_CLAUDE_CMD="$S/claude-fail" python3 "$TOK" --repos acme/plan 2>&1 </dev/null); rc=$?
[ "$rc" != 0 ] && [ ! -s "$SEEN" ] && ok "a failed login stores nothing" || no "a failed login stores nothing"
grep -q "gh secret set" <<<"$out" && ok "a failure explains the manual fallback" || no "a failure explains the manual fallback"
out=$(env -u CLAUDE_CODE_OAUTH_TOKEN -u ANTHROPIC_API_KEY CREW_CLAUDE_CMD="$S/claude-none" python3 "$TOK" --repos acme/plan 2>&1 </dev/null); rc=$?
[ "$rc" != 0 ] && [ ! -s "$SEEN" ] && ok "no token in the output stores nothing" || no "no token in the output stores nothing"
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
# a re-run: the secret already exists everywhere, so no login starts and nothing is stored again
: > "$SEEN"; out=$(STUB_HAVE_SECRET=CLAUDE_CODE_OAUTH_TOKEN env -u CLAUDE_CODE_OAUTH_TOKEN -u ANTHROPIC_API_KEY CREW_CLAUDE_CMD="$S/claude-fail" python3 "$TOK" --repos acme/plan,acme/app 2>&1 </dev/null); rc=$?
[ "$rc" = 0 ] && [ ! -s "$SEEN" ] && grep -q "already set" <<<"$out" && ok "an existing secret skips the login and stores nothing" || no "an existing secret skips the login (rc=$rc): $out"
: > "$SEEN"; out=$(STUB_HAVE_SECRET=CLAUDE_CODE_OAUTH_TOKEN env -u CLAUDE_CODE_OAUTH_TOKEN -u ANTHROPIC_API_KEY CREW_CLAUDE_CMD="$S/claude-ok" python3 "$TOK" --repos acme/plan --force 2>&1 </dev/null)
grep -q "$FAKE" "$SEEN" && ok "--force replaces an existing secret" || no "--force replaces an existing secret"
# a truncated capture is rejected (the real tool once interleaved URL text into the token)
cat > "$S/claude-short" <<EOS
#!/usr/bin/env bash
echo "Your OAuth token (valid for 1 year):"; echo "sk-ant-oat01-$(printf 'C%.0s' $(seq 1 30))"
EOS
chmod +x "$S/claude-short"; : > "$SEEN"
out=$(env -u CLAUDE_CODE_OAUTH_TOKEN -u ANTHROPIC_API_KEY CREW_CLAUDE_CMD="$S/claude-short" python3 "$TOK" --repos acme/plan 2>&1 </dev/null); rc=$?
[ "$rc" != 0 ] && [ ! -s "$SEEN" ] && grep -q "too short" <<<"$out" && ok "a truncated token is rejected and not stored" || no "a truncated token is rejected (rc=$rc): $out"
# a credential that fails the live check is never stored
: > "$SEEN"; out=$(env -u CLAUDE_CODE_OAUTH_TOKEN -u ANTHROPIC_API_KEY CREW_VERIFY_CMD=false CREW_CLAUDE_CMD="$S/claude-ok" python3 "$TOK" --repos acme/plan 2>&1 </dev/null); rc=$?
[ "$rc" != 0 ] && [ ! -s "$SEEN" ] && grep -q "does not work" <<<"$out" && ok "a login token that fails the check is not stored" || no "a login token that fails the check (rc=$rc): $out"
: > "$SEEN"; out=$(env -u ANTHROPIC_API_KEY CREW_VERIFY_CMD=false CLAUDE_CODE_OAUTH_TOKEN="$FAKE" python3 "$TOK" --repos acme/plan 2>&1 </dev/null); rc=$?
[ "$rc" != 0 ] && [ ! -s "$SEEN" ] && ok "an env token that fails the check is not stored" || no "an env token that fails the check (rc=$rc)"
# a full-screen UI that repaints: the login URL is shown, then erased and the token printed on the same screen.
# Joining the raw output would scramble it; the virtual screen reproduces what a terminal shows.
cat > "$S/claude-tui" <<EOS
#!/usr/bin/env bash
printf 'Sign in:\\n\\033]8;id=1;https://claude.com/cai/oauth/authorize?code=true&state=abc\\033\\\\https://claude.com/cai/oauth/authorize?code=true&sta\\033]8;;\\033\\\\\\n'
printf ' Paste code here if prompted >\\n'
printf '\\033[2K\\033[1A\\033[2K\\033[1A\\033[2K\\033[1A\\033[2K\\r'
printf 'Your OAuth token (valid for 1 year):\\n\\n%s\\n\\n Store this token securely.\\n' "$FAKE"
EOS
chmod +x "$S/claude-tui"; : > "$SEEN"
out=$(BROWSER=true env -u CLAUDE_CODE_OAUTH_TOKEN -u ANTHROPIC_API_KEY CREW_CLAUDE_CMD="$S/claude-tui" python3 "$TOK" --repos acme/plan 2>&1 </dev/null); rc=$?
[ "$rc" = 0 ] && grep -q "$FAKE" "$SEEN" && ok "a repainted full-screen UI: the whole token is captured and stored" || no "a repainted UI: token captured (rc=$rc): $out"
if grep -q "sk-ant" <<<"$out"; then no "nothing of the token is echoed from a repainting UI"; else ok "nothing of the token is echoed from a repainting UI"; fi
grep -q "claude.com/cai/oauth/authorize" <<<"$out" && ok "the login URL is shown to the user" || no "the login URL is shown to the user: $out"
rm -rf "$S"; echo "claude-token.test: $pass passed, $failn failed"; [ "$failn" = 0 ]
