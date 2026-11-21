#!/usr/bin/env bash
# Tests for scripts/crew using a stub `gh` first on PATH (no network).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; CREW="$HERE/../scripts/crew"; pass=0; failn=0
ok() { echo "ok   $1"; pass=$((pass+1)); }; no() { echo "FAIL $1"; failn=$((failn+1)); }
S=$(mktemp -d); mkdir -p "$S/bin"; LOG="$S/gh.log"; : > "$LOG"
cat > "$S/bin/gh" <<GH
#!/usr/bin/env bash
echo "\$*" >> "$LOG"
case "\$1 \$2" in
  "auth status") exit 0 ;;
  "secret list") [ -n "\${STUB_NO_SECRETS:-}" ] || printf '[{"name":"CLAUDE_CODE_OAUTH_TOKEN"},{"name":"CREW_REPO_TOKEN"}]' | jq -r '.[].name'; exit 0 ;;
esac
case "\$1" in api) case "\$2" in repos/missing/*|repos/missing) exit 1 ;; *) echo '{}' ;; esac ;; esac
exit 0
GH
chmod +x "$S/bin/gh"; export PATH="$S/bin:$PATH"
out=$(bash "$CREW" init --plan --project demo --plan-repo acme/plan --code-repo acme/app 2>&1)
grep -q "PLAN   create private repo acme/plan" <<<"$out" && ok "init --plan lists the plan repo" || no "init --plan lists the plan repo"
grep -q "label 'needs-rescue'" <<<"$out" && ok "init --plan lists labels" || no "init --plan lists labels"
grep -q "acme/app that installs" <<<"$out" && ok "init --plan lists callers per repo" || no "init --plan lists callers per repo"
if grep -qE 'repo create|label|POST|secret set|pr create' "$LOG"; then no "init --plan makes no changes"; else ok "init --plan makes no changes"; fi
bash "$CREW" init --plan --project demo --plan-repo bad --code-repo acme/app >/dev/null 2>&1 && no "bad repo name rejected" || ok "bad repo name rejected"
bash "$CREW" init --plan --project demo --plan-repo acme/plan >/dev/null 2>&1 && no "missing code repo rejected" || ok "missing code repo rejected"
bash "$CREW" init --plan --project demo --plan-repo acme/plan --code-repo acme/app --runner cron >/dev/null 2>&1 && no "bad runner rejected" || ok "bad runner rejected"
P="$S/crew.json"; jq '.repos.plan="acme/plan" | .repos.code=["acme/app"]' "$HERE/../examples/domain-pack/crew.json" > "$P"
out=$(bash "$CREW" doctor "$P" 2>&1); rc=$?
grep -q "OK     crew.json is valid" <<<"$out" && [ "$rc" = 0 ] && ok "doctor passes on a healthy setup" || no "doctor passes on a healthy setup: rc=$rc"
out=$(STUB_NO_SECRETS=1 bash "$CREW" doctor "$P" 2>&1); grep -q "WARN   acme/app: CLAUDE_CODE_OAUTH_TOKEN missing" <<<"$out" && ok "doctor warns on a missing secret" || no "doctor warns on a missing secret"
jq '.repos.code=["missing/app"]' "$P" > "$S/c2.json"; bash "$CREW" doctor "$S/c2.json" >/dev/null 2>&1 && no "doctor fails on an unreachable repo" || ok "doctor fails on an unreachable repo"
bash "$CREW" doctor "$S/none.json" >/dev/null 2>&1 && no "doctor fails without crew.json" || ok "doctor fails without crew.json"
out=$(bash "$CREW" apps create --crew "$P" --plan 2>&1)
grep -q "PLAN   create GitHub App example-lead" <<<"$out" && ok "apps create --plan lists one app per role" || no "apps create --plan lists one app per role"
[ "$(grep -c '^PLAN   create GitHub App' <<<"$out")" = 4 ] && ok "apps create --plan covers every role" || no "apps create --plan covers every role"
bash "$CREW" apps create --crew "$S/none.json" --plan >/dev/null 2>&1 && no "apps create needs a crew.json" || ok "apps create needs a crew.json"
bash "$CREW" apps wat --crew "$P" >/dev/null 2>&1 && no "apps rejects an unknown subcommand" || ok "apps rejects an unknown subcommand"
out=$(bash "$CREW" init --plan --project demo --plan-repo acme/plan --code-repo acme/app 2>&1)
grep -q "acme/app that installs the crew workflow callers for a code repo" <<<"$out" && ok "init --plan: code repos get the code callers" || no "init --plan: code repos get the code callers"
grep -q "acme/plan that installs the crew workflow callers for the plan repo" <<<"$out" && ok "init --plan: plan repo gets the plan callers" || no "init --plan: plan repo gets the plan callers"
# which templates each kind installs (dry-run of the helper)
c=$(bash "$CREW" _install-callers acme/app h/r main actions /tmp 1 acme/plan code); p=$(bash "$CREW" _install-callers acme/plan h/r main actions /tmp 1 acme/plan plan)
[ "$c" = "         would add: crew-review.yml crew-wake.yml " ] && ok "code repo callers: wake and review only" || no "code repo callers: $c"
grep -q "crew-schedule-worker.yml" <<<"$p" && ! grep -q "crew-review.yml" <<<"$p" && ok "plan repo callers: schedules, no review" || no "plan repo callers: $p"
p=$(bash "$CREW" _install-callers acme/plan h/r main routines /tmp 1 acme/plan plan); ! grep -q "crew-schedule" <<<"$p" && ok "routines runner installs no schedule callers" || no "routines runner installs no schedule callers"
# zero-paste flow
out=$(bash "$CREW" init --plan --project demo --plan-repo acme/plan --code-repo acme/app 2>&1)
grep -q "log in to Claude (browser) and store CLAUDE_CODE_OAUTH_TOKEN in: acme/plan,acme/app" <<<"$out" && ok "init --plan: Claude login stores the token in every repo" || no "init --plan: Claude login stores the token in every repo"
grep -q "create ONE GitHub App for the crew" <<<"$out" && ok "init --plan: default identity is one shared App" || no "init --plan: default identity is one shared App"
if grep -qE "gh secret set|paste" <<<"$out"; then no "init --plan asks the user to paste nothing"; else ok "init --plan asks the user to paste nothing"; fi
out=$(bash "$CREW" init --plan --project demo --plan-repo acme/plan --code-repo acme/app --identity roles 2>&1); grep -q "one GitHub App per role" <<<"$out" && ok "identity=roles creates one App per role" || no "identity=roles creates one App per role"
out=$(bash "$CREW" init --plan --project demo --plan-repo acme/plan --code-repo acme/app --no-claude-login 2>&1); grep -q "claude login skipped" <<<"$out" && ok "--no-claude-login skips the login" || no "--no-claude-login skips the login"
bash "$CREW" init --plan --project demo --plan-repo acme/plan --code-repo acme/app --identity solo >/dev/null 2>&1 && no "old identity name rejected" || ok "old identity name rejected"
out=$(bash "$CREW" apps create --crew "$P" --single --plan 2>&1); [ "$(grep -c '^PLAN   create GitHub App' <<<"$out")" = 1 ] && grep -q "example-crew" <<<"$out" && ok "apps create --single makes exactly one App" || no "apps create --single makes exactly one App: $out"
out=$(bash "$CREW" activate --crew "$P" --yes 2>&1); grep -q "enable crew-schedule-worker in acme/plan" <<<"$out" && ok "activate enables the schedules when the Claude token exists" || no "activate enables the schedules: $out"
out=$(STUB_NO_SECRETS=1 bash "$CREW" activate --crew "$P" --yes 2>&1); grep -q "no Claude token in acme/plan" <<<"$out" && ok "activate leaves schedules off without a Claude token" || no "activate leaves schedules off without a Claude token"
bash "$CREW" activate --crew "$S/none.json" --yes >/dev/null 2>&1 && no "activate needs a crew.json" || ok "activate needs a crew.json"
rm -rf "$S"; echo "crew-cli.test: $pass passed, $failn failed"; [ "$failn" = 0 ]
