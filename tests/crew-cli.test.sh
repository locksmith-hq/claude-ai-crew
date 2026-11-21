#!/usr/bin/env bash
# Tests for scripts/crew using a stub `gh` first on PATH (no network).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; CREW="$HERE/../scripts/crew"; pass=0; failn=0
ok() { echo "ok   $1"; pass=$((pass+1)); }; no() { echo "FAIL $1"; failn=$((failn+1)); }
S=$(mktemp -d); mkdir -p "$S/bin"; LOG="$S/gh.log"; : > "$LOG"
# a token-shaped fake built at runtime, so this file holds no token literal
FAKETOK="gh""o_FAKELOGIN$(printf '0%.0s' $(seq 1 30))"; export FAKETOK
cat > "$S/bin/gh" <<GH
#!/usr/bin/env bash
echo "\$*" >> "$LOG"
case "\$1 \$2" in
  "auth status") echo "  - Token scopes: 'gist', 'read:org', 'repo'"; exit 0 ;;
  "auth token") echo "\$FAKETOK"; exit 0 ;;
  "secret set") cat >> "$S/secret.seen"; exit 0 ;;
  "secret list") [ -n "\${STUB_NO_SECRETS:-}" ] || printf '[{"name":"CLAUDE_CODE_OAUTH_TOKEN"},{"name":"CREW_REPO_TOKEN"}]' | jq -r '.[].name'; exit 0 ;;
esac
case "\$1" in api) case "\$2" in repos/missing/*|repos/missing) exit 1 ;; users/acme) echo Organization ;; users/someone) echo User ;; *) echo '{}' ;; esac ;; esac
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
# fully scripted flow
out=$(bash "$CREW" init --plan --project demo --plan-repo acme/plan --code-repo acme/app 2>&1)
grep -q "store the Claude credential" <<<"$out" && grep -q "else a browser login" <<<"$out" && ok "init --plan: Claude credential comes from the environment first" || no "init --plan: Claude credential comes from the environment first"
grep -q "store your gh login as CREW_REPO_TOKEN in: acme/plan,acme/app" <<<"$out" && ok "init --plan: default identity is the gh login (no web)" || no "init --plan: default identity is the gh login: $out"
grep -q "PLAN   activate" <<<"$out" && ok "init --plan: activation is part of init" || no "init --plan: activation is part of init"
if grep -qiE "browser click|paste|create ONE GitHub App" <<<"$out"; then no "default init needs no web step and no pasting"; else ok "default init needs no web step and no pasting"; fi
out=$(bash "$CREW" init --plan --project demo --plan-repo acme/plan --code-repo acme/app --identity app 2>&1); grep -q "create ONE GitHub App" <<<"$out" && ok "identity=app is the opt-in shared App" || no "identity=app is the opt-in shared App"
out=$(bash "$CREW" init --plan --project demo --plan-repo acme/plan --code-repo acme/app --identity single 2>&1); grep -q "create ONE GitHub App" <<<"$out" && ok "identity=single is an alias of app" || no "identity=single is an alias of app"
out=$(bash "$CREW" init --plan --project demo --plan-repo acme/plan --code-repo acme/app --no-activate 2>&1); grep -q "NEXT   then run: crew activate" <<<"$out" && ok "--no-activate leaves activation for later" || no "--no-activate leaves activation for later"
# the gh token is piped into each repo's secret and never shown
: > "$S/secret.seen"; out=$(bash "$CREW" _store-repo-token acme/plan acme/app 2>&1); rc=$?
[ "$rc" = 0 ] && [ "$(grep -o "$FAKETOK" "$S/secret.seen" | wc -l | tr -d ' ')" = 2 ] && ok "gh token reaches gh secret set once per repo through stdin" || no "gh token reaches gh secret set (rc=$rc)"
if grep -q "$FAKETOK" <<<"$out" || grep -q "$FAKETOK" "$LOG"; then no "the gh token is never printed or passed as an argument"; else ok "the gh token is never printed or passed as an argument"; fi
out=$(bash "$CREW" init --plan --project demo --plan-repo acme/plan --code-repo acme/app --identity roles 2>&1); grep -q "one GitHub App per role" <<<"$out" && ok "identity=roles creates one App per role" || no "identity=roles creates one App per role"
bash "$CREW" init --plan --project demo --plan-repo acme/plan --code-repo acme/app --identity solo >/dev/null 2>&1 && no "old identity name rejected" || ok "old identity name rejected"
out=$(bash "$CREW" apps create --crew "$P" --single --plan 2>&1); [ "$(grep -c '^PLAN   create GitHub App' <<<"$out")" = 1 ] && grep -q "example-crew" <<<"$out" && ok "apps create --single makes exactly one App" || no "apps create --single makes exactly one App: $out"
out=$(bash "$CREW" activate --crew "$P" --yes 2>&1); grep -q "enable crew-schedule-worker in acme/plan" <<<"$out" && ok "activate enables the schedules when the Claude token exists" || no "activate enables the schedules: $out"
out=$(STUB_NO_SECRETS=1 bash "$CREW" activate --crew "$P" --yes 2>&1); grep -q "no Claude token in acme/plan" <<<"$out" && ok "activate leaves schedules off without a Claude token" || no "activate leaves schedules off without a Claude token"
bash "$CREW" activate --crew "$S/none.json" --yes >/dev/null 2>&1 && no "activate needs a crew.json" || ok "activate needs a crew.json"
# the real (non-dry) apps path, with python3 stubbed: empty option arrays must not break bash 3.2 under set -u
mkdir -p "$S/pybin"; cat > "$S/pybin/python3" <<PYS
#!/usr/bin/env bash
echo "\$*" >> "$S/py.args"
exit 0
PYS
chmod +x "$S/pybin/python3"
out=$(PATH="$S/pybin:$PATH" bash "$CREW" apps create --crew "$P" --single 2>&1); rc=$?
[ "$rc" = 0 ] && ! grep -q "unbound variable" <<<"$out" && grep -q -- "--single" "$S/py.args" && ok "apps create --single runs (no unbound-variable error)" || no "apps create --single runs: rc=$rc $out"
: > "$S/py.args"; out=$(PATH="$S/pybin:$PATH" bash "$CREW" apps create --crew "$P" --org --role lead 2>&1); rc=$?
[ "$rc" = 0 ] && grep -q -- "--org" "$S/py.args" && ! grep -q -- "--single" "$S/py.args" && ok "apps create --org --role passes only --org" || no "apps create --org --role: rc=$rc $out"
# an organization-owned plan repo gets an organization-owned App automatically
: > "$S/py.args"; PATH="$S/pybin:$PATH" bash "$CREW" apps create --crew "$P" --single >/dev/null 2>&1
grep -q -- "--org" "$S/py.args" && ok "apps create detects an organization owner and passes --org" || no "apps create detects an organization owner: $(cat "$S/py.args")"
jq '.repos.plan="someone/plan" | .repos.code=["someone/app"]' "$P" > "$S/u.json"; : > "$S/py.args"; PATH="$S/pybin:$PATH" bash "$CREW" apps create --crew "$S/u.json" --single >/dev/null 2>&1
grep -q -- "--org" "$S/py.args" && no "a personal owner does not get --org" || ok "a personal owner does not get --org"
bash "$CREW" init --plan --project demo --plan-repo acme/plan --code-repo acme/app --force-claude >/dev/null 2>&1 && ok "--force-claude is accepted" || no "--force-claude is accepted"
rm -rf "$S"; echo "crew-cli.test: $pass passed, $failn failed"; [ "$failn" = 0 ]
