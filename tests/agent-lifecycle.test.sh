#!/usr/bin/env bash
# Offline tests for run-meta.sh, bg.sh, agent-preflight.sh, agent-identity.sh (selftest) and agent-start.sh,
# using throwaway git repos (a plan repo with crew.json and a code repo, each with a bare "origin").
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; S="$(cd "$HERE/../scripts" && pwd)"; pass=0; failn=0
ok() { echo "ok   $1"; pass=$((pass+1)); }; no() { echo "FAIL $1"; failn=$((failn+1)); }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com

# fixtures: plan repo (crew.json, lessons, a change) and code repo
mkrepo() { # <name> <owner/name>
  git init -q --bare -b main "$W/$1.git"; git clone -q "$W/$1.git" "$W/$1" 2>/dev/null
  git -C "$W/$1" checkout -q -b main 2>/dev/null; git -C "$W/$1" remote set-url origin "https://github.com/$2.git"
  git -C "$W/$1" config "url.$W/$1.git.insteadOf" "https://github.com/$2.git"
}
mkrepo plan acme/plan; mkrepo code acme/app
jq '.repos.plan="acme/plan" | .repos.code=["acme/app"] | .owner.login="boss"
  | .preflight=[{"name":"present","cmd":"true"},{"name":"soft","cmd":"false","level":"warn","hint":"soft hint"},
                {"name":"fixme","cmd":"test -f \"$FIXFILE\"","fix":"touch \"$FIXFILE\"","wait":3}]' \
  "$HERE/../examples/domain-pack/crew.json" > "$W/plan/crew.json"
mkdir -p "$W/plan/changes/c1"; printf -- '- [ ] 1.1 first\n- [ ] 1.2 second\n' > "$W/plan/changes/c1/tasks.md"
printf '# Lessons\n\n## L1 keep it small\nbody\n' > "$W/plan/lessons.md"
git -C "$W/plan" add -A; git -C "$W/plan" commit -qm init; git -C "$W/plan" push -q origin main
echo x > "$W/code/a.txt"; git -C "$W/code" add -A; git -C "$W/code" commit -qm init; git -C "$W/code" push -q origin main
git -C "$W/plan" fetch -q origin; git -C "$W/code" fetch -q origin
# a bare gh stub and curl stub so preflight needs no network
mkdir -p "$W/bin"; printf '#!/bin/sh\nexit 0\n' > "$W/bin/gh"; cp "$W/bin/gh" "$W/bin/curl"; chmod +x "$W/bin/gh" "$W/bin/curl"
E() { env -i HOME="$W" PATH="$W/bin:$PATH" CREW_PLAN_DIR="$W/plan" CREW_CODE_DIR="$W/code" RUN_META_STATE="$W/meta.env" BG_DIR="$W/bg" FIXFILE="$W/fixed" "$@"; }
mkdir -p "$W/bg"

# ---- run-meta
E bash "$S/run-meta.sh" start worker-a >/dev/null
grep -q '^KIND=worker-a' "$W/meta.env" && ok "start records kind" || no "start records kind"
rep=$(E bash "$S/run-meta.sh" report)
grep -q 'kind: worker-a' <<<"$rep" && grep -q 'plan_head_sha:' <<<"$rep" && grep -q 'full_ci_s:' <<<"$rep" && ok "report has code and plan fields" || no "report fields: $rep"
blk=$(printf '  evaluator: PASS\n' | E bash "$S/run-meta.sh" block 2>&1)
[ "$(head -1 <<<"$blk")" = '```yaml' ] && [ "$(tail -1 <<<"$blk")" = '```' ] && grep -q 'evaluator: PASS' <<<"$blk" && ok "block is one fenced yaml block" || no "block: $blk"
# a tick on a plan branch
git -C "$W/plan" checkout -q -b claude/change-c1; sed -i.bak 's/- \[ \] 1.1/- [x] 1.1/' "$W/plan/changes/c1/tasks.md"; rm -f "$W/plan/changes/c1/tasks.md.bak"
git -C "$W/plan" commit -qam "tick 1.1"
sed -i.bak "s/^START_EPOCH=.*/START_EPOCH=$(( $(date +%s) - 100 ))/" "$W/meta.env"; rm -f "$W/meta.env.bak"
(cd "$W/plan" && E bash "$S/run-meta.sh" push-check) >/dev/null 2>&1 && no "push-check refuses a tick without eval" || ok "push-check refuses a tick without eval"
(cd "$W/code" && E bash "$S/run-meta.sh" push-check) >/dev/null 2>&1 && ok "push-check passes where nothing is ticked" || no "push-check passes in the code repo"
w=$(printf '  evaluator: n/a\n' | E bash "$S/run-meta.sh" block 2>&1 >/dev/null)
grep -q 'ticked 1 task' <<<"$w" && ok "block warns on evaluator n/a with ticks" || no "evaluator n/a warning: $w"
E bash "$S/run-meta.sh" eval FAIL; (cd "$W/plan" && E bash "$S/run-meta.sh" push-check) >/dev/null 2>&1 && no "eval FAIL still blocks" || ok "eval FAIL still blocks"
E bash "$S/run-meta.sh" eval PASS; (cd "$W/plan" && E bash "$S/run-meta.sh" push-check) >/dev/null 2>&1 && ok "eval PASS lets the push through" || no "eval PASS lets the push through"
E bash "$S/run-meta.sh" eval MAYBE >/dev/null 2>&1; [ $? = 2 ] && ok "eval rejects other verdicts" || no "eval rejects other verdicts"
git -C "$W/plan" checkout -q main; rm -f "$W/meta.env"

# ---- key_env / id_env aliases and the App id lookup
jq '.roles.lead.key_env="OLDKEY_LEAD" | .roles.lead.id_env="OLDID_LEAD"' "$W/plan/crew.json" > "$W/crew4.json"
out=$(E env CREW_CONFIG="$W/crew4.json" AGENT_API_URL=http://127.0.0.1:9 OLDKEY_LEAD=xx bash "$S/agent-identity.sh" setup lead 2>&1); rc=$?
grep -q "OLDID_LEAD is not set" <<<"$out" && ok "crew.json key_env/id_env name the variables" || no "crew.json key_env/id_env name the variables: rc=$rc $out"
# key_env names a variable this environment lacks, but AGENT_APP_KEY_<ROLE> is set: the role name wins
kv() { E env CREW_CONFIG="$W/crew4.json" "$@" bash "$S/agent-identity.sh" keyvar lead; }
[ "$(kv AGENT_APP_KEY_LEAD=x)" = AGENT_APP_KEY_LEAD ] && [ "$(kv OLDKEY_LEAD=y AGENT_APP_KEY_LEAD=x)" = OLDKEY_LEAD ] && [ "$(kv)" = OLDKEY_LEAD ] &&
  ok "keyvar: key_env when set, else AGENT_APP_KEY_<ROLE>" || no "keyvar: $(kv AGENT_APP_KEY_LEAD=x) $(kv)"
cat > "$W/appsrv.py" <<'PYS'
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        open(sys.argv[1], "a").write(self.path + "\n")
        body = json.dumps({"id": 4242}).encode() if self.path.startswith("/apps/") else b"{}"
        self.send_response(200); self.send_header("Content-Type", "application/json"); self.end_headers(); self.wfile.write(body)
srv = HTTPServer(("127.0.0.1", 0), H); print(srv.server_port, flush=True); srv.serve_forever()
PYS
python3 "$W/appsrv.py" "$W/hits.log" > "$W/appsrv.port" & APPSRV=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$W/appsrv.port" ] && break; sleep 0.3; done
REALBIN="$(dirname "$(command -v curl)"):$(dirname "$(command -v jq)"):/usr/bin:/bin"   # the test bin stubs curl; this check needs the real one
out=$(E env PATH="$REALBIN" AGENT_API_URL="http://127.0.0.1:$(cat "$W/appsrv.port")" AGENT_APP_KEY_LEAD="$(printf "not a key" | openssl base64 -A)" bash "$S/agent-identity.sh" setup lead 2>&1)
grep -q "^/apps/example-lead" "$W/hits.log" && ok "a missing App id is looked up by slug (GET /apps/<slug>)" || no "App id lookup by slug: $(cat "$W/hits.log" 2>/dev/null) $out"
kill "$APPSRV" 2>/dev/null; wait "$APPSRV" 2>/dev/null
# an App id in crew.json is used without any lookup
jq '.roles.lead.app_id=4242' "$W/plan/crew.json" > "$W/crew5.json"
: > "$W/hits.log"
out=$(E env CREW_CONFIG="$W/crew5.json" AGENT_API_URL=http://127.0.0.1:9 AGENT_APP_KEY_LEAD="$(printf "not a key" | openssl base64 -A)" bash "$S/agent-identity.sh" setup lead 2>&1)
grep -q "is not the base64 of a private key" <<<"$out" && ok "roles.<role>.app_id is used (the run got past the id step without a lookup)" || no "roles.<role>.app_id is used: $out"
grep -q "roles\\\[\\\"\$role\\\"\\\]\.bot_id\|bot_id" "$S/agent-identity.sh" && ok "the bot user id is read from roles.<role>.bot_id before any lookup" || no "agent-identity.sh does not read roles.<role>.bot_id"
# ---- bg.sh
E bash "$S/bg.sh" start ok 20 -- sh -c 'echo hello; exit 0' >/dev/null
out=$(E bash "$S/bg.sh" wait ok 10); rc=$?
[ "$rc" = 0 ] && grep -q hello <<<"$out" && ok "bg runs and reports exit 0" || no "bg ok: rc=$rc $out"
[ "$(E bash "$S/bg.sh" status ok)" = "done 0" ] && ok "bg status done" || no "bg status done"
E bash "$S/bg.sh" start bad 20 -- sh -c 'exit 3' >/dev/null; E bash "$S/bg.sh" wait bad 10 >/dev/null; [ $? = 3 ] && ok "bg propagates the exit code" || no "bg exit code"
E bash "$S/bg.sh" start slow 1 -- sleep 30 >/dev/null; out=$(E bash "$S/bg.sh" wait slow 10); rc=$?
[ "$rc" = 137 ] && grep -q 'killed by timeout' <<<"$out" && ok "bg kills at the timeout" || no "bg timeout: rc=$rc $out"
E bash "$S/bg.sh" start run 20 -- sleep 5 >/dev/null; [ "$(E bash "$S/bg.sh" status run)" = running ] && ok "bg status running" || no "bg status running"
E bash "$S/bg.sh" wait run 1 >/dev/null; [ $? = 124 ] && ok "bg wait gives 124 while running" || no "bg wait 124"
E bash "$S/bg.sh" start nostdin 5 -- cat >/dev/null; E bash "$S/bg.sh" wait nostdin 4 >/dev/null; [ $? = 0 ] && ok "bg gives the job no stdin" || no "bg stdin"
[ "$(grep -c . "$W/bg/bg-times")" -ge 4 ] && grep -q '^ok [0-9]* 0$' "$W/bg/bg-times" && ok "bg appends to bg-times" || no "bg-times"
E bash "$S/bg.sh" start piped 5 -- sleep 3 | (cat >/dev/null); ok "bg start does not hold a pipe open"
E bash "$S/bg.sh" wait run 10 >/dev/null 2>&1

# ---- preflight
out=$(E bash "$S/agent-preflight.sh"); rc=$?
[ "$rc" = 0 ] && grep -q '^OK     present' <<<"$out" && grep -q '^WARN   soft *soft hint' <<<"$out" && grep -q '^FIXED  fixme' <<<"$out" && ok "preflight: OK, WARN with hint, FIXED" || no "preflight lines (rc=$rc): $out"
jq '.preflight += [{"name":"must","cmd":"false"}]' "$W/plan/crew.json" > "$W/crew2.json"
out=$(E env CREW_CONFIG="$W/crew2.json" bash "$S/agent-preflight.sh"); rc=$?
[ "$rc" = 1 ] && grep -q '^FAIL   must' <<<"$out" && ok "preflight: a fail-level check exits 1" || no "preflight fail exit (rc=$rc)"

# ---- identity selftest (offline) and unknown role
out=$(E bash "$S/agent-identity.sh" selftest 2>&1); [ "$out" = "agent-identity selftest: OK" ] && ok "identity selftest" || no "identity selftest: $out"
out=$(E bash "$S/agent-identity.sh" setup nobody 2>&1); [ $? = 1 ] && grep -q 'unknown role' <<<"$out" && ok "identity refuses an unknown role" || no "identity unknown role: $out"

# ---- agent-start with stubs
rm -f "$W/fixed" "$W/meta.env"
git -C "$W/plan" checkout -q --detach HEAD~0
out=$(E bash "$S/agent-start.sh" worker-a worker-a 2>&1); rc=$?
[ "$rc" = 0 ] && ok "agent-start exits 0 with a clean preflight" || no "agent-start exit (rc=$rc): $out"
grep -q 'run-meta: started worker-a' <<<"$out" && grep -q '== preflight' <<<"$out" && ok "agent-start starts meta and preflight" || no "agent-start sections"
grep -q 'WARN   identity: no AGENT_APP_KEY_WORKER_A key' <<<"$out" && ok "agent-start warns with no key anywhere" || no "identity warn: $out"
grep -q '^## L1 keep it small' <<<"$out" && ! grep -q '^# Lessons' <<<"$out" && ok "agent-start prints active lessons from origin/main" || no "lessons"
for r in plan code; do
  h="$W/$r/.git/hooks/pre-push"
  [ -x "$h" ] && grep -q "$S/run-meta.sh" "$h" && ok "pre-push hook in $r calls the harness run-meta" || no "hook in $r"
done
# the installed hook refuses an unevaluated tick
git -C "$W/plan" checkout -q claude/change-c1; sed -i.bak "s/^START_EPOCH=.*/START_EPOCH=$(( $(date +%s) - 100 ))/" "$W/meta.env"; rm -f "$W/meta.env.bak"
(cd "$W/plan" && env -i HOME="$W" PATH="$PATH" RUN_META_STATE="$W/meta.env" sh .git/hooks/pre-push) >/dev/null 2>&1 && no "hook refuses unevaluated ticks" || ok "hook refuses unevaluated ticks"
git -C "$W/plan" checkout -q main
# stale scratch checkout moves to origin/main
git -C "$W/code" checkout -q -b claude/scratch-1; git -C "$W/code" push -q origin claude/scratch-1:main 2>/dev/null
git -C "$W/code" checkout -q main; git -C "$W/code" reset -q --hard origin/main
echo y > "$W/code/b.txt"; git -C "$W/code" add -A; git -C "$W/code" commit -qm more; git -C "$W/code" push -q origin main
git -C "$W/code" checkout -q -b claude/scratch-2 HEAD~1
E bash "$S/agent-start.sh" worker-a worker-a >/dev/null 2>&1
[ "$(git -C "$W/code" rev-parse HEAD)" = "$(git -C "$W/code" rev-parse origin/main)" ] && ok "stale scratch checkout moved to origin/main" || no "stale checkout not moved"
# identity failure modes
out=$(E env AGENT_APP_KEY_LEAD=x bash "$S/agent-start.sh" worker-a worker-a 2>&1); rc=$?
[ "$rc" = 1 ] && grep -q 'FAIL identity: this environment holds App keys but no AGENT_APP_KEY_WORKER_A' <<<"$out" && ok "keys present but none for the persona: FAIL" || no "identity no-fallback (rc=$rc)"
out=$(E env AGENT_APP_KEY_LEAD=x bash "$S/agent-start.sh" worker-a 2>&1); grep -q 'no persona was passed' <<<"$out" && ok "keys present and no persona: FAIL" || no "no persona message"
out=$(E bash "$S/agent-start.sh" research research 2>&1); rc=$?
[ "$rc" = 1 ] && grep -q 'research has open internet' <<<"$out" && ok "research never runs as the owner" || no "research identity (rc=$rc)"
out=$(E env CREW_CONFIG="$W/crew2.json" bash "$S/agent-start.sh" worker-a worker-a 2>&1); [ $? = 1 ] && ok "agent-start exits 1 on a preflight FAIL" || no "agent-start preflight fail exit"
# stack check
jq '.stack_checks=[{"name":"up","cmd":"true"}]' "$W/plan/crew.json" > "$W/crew3.json"
out=$(E env CREW_CONFIG="$W/crew3.json" bash "$S/harness-check.sh"); [ "$out" = "PASS  up" ] && ok "harness-check passes" || no "harness-check: $out"
jq '.stack_checks=[{"name":"down","cmd":"false"}]' "$W/plan/crew.json" > "$W/crew3.json"
E env CREW_CONFIG="$W/crew3.json" bash "$S/harness-check.sh" >/dev/null; [ $? = 1 ] && ok "harness-check fails on a failing check" || no "harness-check fail"

echo "agent-lifecycle.test: $pass passed, $failn failed"; [ "$failn" = 0 ]
