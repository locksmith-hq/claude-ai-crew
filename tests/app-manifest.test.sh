#!/usr/bin/env bash
# Tests for scripts/lib/app_manifest.py with a fake GitHub API and a stub `gh` (no network, no browser).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; APP="$HERE/../scripts/lib/app_manifest.py"; pass=0; failn=0
ok() { echo "ok   $1"; pass=$((pass+1)); }; no() { echo "FAIL $1"; failn=$((failn+1)); }
command -v python3 >/dev/null || { echo "app-manifest.test: python3 missing, skipped"; exit 0; }
S=$(mktemp -d); mkdir -p "$S/bin"; GHLOG="$S/gh.log"; KEYFILE="$S/key.seen"; : > "$GHLOG"
cat > "$S/bin/gh" <<GH
#!/usr/bin/env bash
echo "\$*" >> "$GHLOG"
if [ "\$1 \$2" = "secret set" ]; then cat > "$KEYFILE"; fi
exit 0
GH
chmod +x "$S/bin/gh"; export PATH="$S/bin:$PATH"
# fake GitHub API: POST /app-manifests/<code>/conversions
cat > "$S/api.py" <<'PY'
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_POST(self):
        if "/app-manifests/good/conversions" in self.path:
            body = json.dumps({"id": 4242, "slug": "demo-lead", "pem": "-----BEGIN " + "RSA PRIVATE" + " KEY-----\nFAKEKEYMATERIAL\n-----END " + "RSA PRIVATE" + " KEY-----\n"})
            self.send_response(201); self.send_header("Content-Type", "application/json"); self.end_headers(); self.wfile.write(body.encode())
        else:
            self.send_response(404); self.end_headers()
srv = HTTPServer(("127.0.0.1", 0), H); print(srv.server_port, flush=True); srv.serve_forever()
PY
python3 "$S/api.py" > "$S/api.port" & APIPID=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$S/api.port" ] && break; sleep 0.3; done
API="http://127.0.0.1:$(cat "$S/api.port")"
PORT=$((20000 + RANDOM % 20000))
CREW_API_BASE="$API" python3 "$APP" --project demo --role lead --owner acme --repos acme/plan,acme/app --port "$PORT" --no-browser --timeout 20 > "$S/out.txt" 2> "$S/err.txt" & APPPID=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do curl -fsS "http://127.0.0.1:$PORT/" -o "$S/page.html" 2>/dev/null && break; sleep 0.3; done
grep -q 'settings/apps/new' "$S/page.html" && ok "page posts to GitHub's app creation URL" || no "page posts to GitHub's app creation URL"
grep -q 'demo-lead' "$S/page.html" && ok "manifest names the app <project>-<role>" || no "manifest names the app <project>-<role>"
grep -q '127.0.0.1' "$S/page.html" && grep -q 'callback' "$S/page.html" && ok "manifest redirects to the local callback" || no "manifest redirects to the local callback"
M=$(python3 - "$S/page.html" <<'PY'
import re, sys, html, json
t = open(sys.argv[1]).read(); m = re.search(r'name=manifest value="([^"]*)"', t)
d = json.loads(html.unescape(m.group(1))); print(json.dumps({"hook": d["hook_attributes"]["active"], "events": d["default_events"], "perm": d["default_permissions"].get("contents")}))
PY
)
[ "$M" = '{"hook": false, "events": [], "perm": "write"}' ] && ok "manifest: no webhook, no events, worker-style permissions" || no "manifest: no webhook, no events: $M"
STATE=$(grep -oE 'state=[0-9a-f]+' "$S/page.html" | head -1 | cut -d= -f2)
code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/callback?code=good&state=wrong"); [ "$code" = 400 ] && ok "callback with a wrong state is rejected" || no "callback with a wrong state is rejected: $code"
code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/callback?code=good&state=$STATE"); [ "$code" = 200 ] && ok "callback with the right state is accepted" || no "callback with the right state is accepted: $code"
wait "$APPPID"; rc=$?
[ "$rc" = 0 ] && ok "script exits 0 after storing" || no "script exits 0 after storing (rc=$rc): $(cat "$S/err.txt")"
grep -q 'secret set AGENT_APP_KEY_LEAD -R acme/plan' "$GHLOG" && grep -q 'secret set AGENT_APP_KEY_LEAD -R acme/app' "$GHLOG" && ok "key stored as a secret in every repo" || no "key stored as a secret in every repo"
grep -q 'variable set AGENT_APP_ID_LEAD -R acme/plan --body 4242' "$GHLOG" && ok "app id stored as a variable" || no "app id stored as a variable"
grep -q 'FAKEKEYMATERIAL' "$KEYFILE" && ok "private key reached gh through stdin" || no "private key reached gh through stdin"
if grep -rq 'FAKEKEYMATERIAL' "$S/out.txt" "$S/err.txt" "$GHLOG"; then no "private key never printed or passed as an argument"; else ok "private key never printed or passed as an argument"; fi
grep -q 'installations/new' "$S/out.txt" && ok "prints the install link" || no "prints the install link"
python3 "$APP" --project demo --role "Bad Role" --owner acme --repos a/b --no-browser >/dev/null 2>&1 && no "invalid role name rejected" || ok "invalid role name rejected"
# --single stores the shared-app names
: > "$GHLOG"; PORT=$((20000 + RANDOM % 20000))
CREW_API_BASE="$API" python3 "$APP" --project demo --role crew --single --owner acme --repos acme/plan --port "$PORT" --no-browser --timeout 20 > "$S/out2.txt" 2> "$S/err2.txt" & APPPID=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do curl -fsS "http://127.0.0.1:$PORT/" -o "$S/page2.html" 2>/dev/null && break; sleep 0.3; done
STATE=$(grep -oE 'state=[0-9a-f]+' "$S/page2.html" | head -1 | cut -d= -f2)
curl -s -o /dev/null "http://127.0.0.1:$PORT/callback?code=good&state=$STATE"; wait "$APPPID"
grep -q 'secret set CREW_APP_KEY -R acme/plan' "$GHLOG" && grep -q 'variable set CREW_APP_ID -R acme/plan --body 4242' "$GHLOG" && ok "--single stores CREW_APP_KEY and CREW_APP_ID" || no "--single stores CREW_APP_KEY and CREW_APP_ID"
kill "$APIPID" 2>/dev/null; wait "$APIPID" 2>/dev/null; rm -rf "$S"
echo "app-manifest.test: $pass passed, $failn failed"; [ "$failn" = 0 ]
