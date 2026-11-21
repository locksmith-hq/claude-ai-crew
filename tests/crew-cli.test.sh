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
out=$(STUB_NO_SECRETS=1 bash "$CREW" doctor "$P" 2>&1); grep -q "WARN   acme/app: secret CLAUDE_CODE_OAUTH_TOKEN missing" <<<"$out" && ok "doctor warns on a missing secret" || no "doctor warns on a missing secret"
jq '.repos.code=["missing/app"]' "$P" > "$S/c2.json"; bash "$CREW" doctor "$S/c2.json" >/dev/null 2>&1 && no "doctor fails on an unreachable repo" || ok "doctor fails on an unreachable repo"
bash "$CREW" doctor "$S/none.json" >/dev/null 2>&1 && no "doctor fails without crew.json" || ok "doctor fails without crew.json"
rm -rf "$S"; echo "crew-cli.test: $pass passed, $failn failed"; [ "$failn" = 0 ]
