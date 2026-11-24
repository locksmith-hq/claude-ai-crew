#!/usr/bin/env python3
"""Create one GitHub App per crew role through GitHub's App manifest flow, entirely on this machine.

How it works (no server of ours is involved):
  1. A tiny local web server serves a page that POSTs the app manifest to GitHub in YOUR browser.
  2. You click "Create GitHub App" on github.com (that click is the only human step).
  3. GitHub redirects your browser to http://127.0.0.1:<port>/callback?code=...; this script catches the code.
  4. It exchanges the code for the app id and private key (POST /app-manifests/<code>/conversions).
  5. The private key is piped straight into `gh secret set` (stdin). It is never printed or written to disk.

Usage: app_manifest.py --project P --role R --owner ORG_OR_USER [--org] [--single] --repos plan/repo,code/repo
                       [--harness-url URL] [--port N] [--no-browser] [--timeout SECS]
Env:   CREW_GITHUB_BASE (default https://github.com): test hook for the page target.
"""
import argparse, json, os, re, subprocess, sys, threading, urllib.request, webbrowser
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs

WEB = os.environ.get("CREW_GITHUB_BASE", "https://github.com")

# Minimal permissions per role kind. Nothing is granted that the role's prompt does not need.
BASE = {"metadata": "read", "contents": "write", "pull_requests": "write", "issues": "write",
        "checks": "read", "actions": "read", "statuses": "read"}
READ_ONLY = {"metadata": "read", "contents": "read", "issues": "write", "pull_requests": "read"}
REVIEW = {"metadata": "read", "contents": "read", "pull_requests": "write", "issues": "write", "statuses": "write", "checks": "read"}

def permissions_for(role):
    if role.startswith("research"): return dict(READ_ONLY)
    if role.startswith("review"): return dict(REVIEW)
    return dict(BASE)

def env_suffix(role):
    return re.sub(r"[^A-Z0-9]", "_", role.upper())

def build_manifest(project, role, port, harness_url):
    return {
        "name": f"{project}-{role}",
        "url": harness_url,
        "redirect_url": f"http://127.0.0.1:{port}/callback",
        "public": False,
        "hook_attributes": {"url": "https://example.invalid/unused", "active": False},
        "default_permissions": permissions_for(role),
        "default_events": [],
    }

def convert(code):
    """Trade the one-time manifest code for the app id and key. Goes through `gh` so TLS certificates are the
    system's (python.org builds on macOS ship without a certificate bundle and fail urllib with CERTIFICATE_VERIFY_FAILED)."""
    r = subprocess.run(["gh", "api", "-X", "POST", f"app-manifests/{code}/conversions"], capture_output=True, text=True)
    if r.returncode: raise RuntimeError((r.stderr or "gh api failed").strip()[:200])
    return json.loads(r.stdout)

def gh(args, stdin=None):
    return subprocess.run(["gh"] + args, input=stdin, text=True, capture_output=True)

def store(key_name, id_name, app, repos):
    """Private key -> secret via stdin; app id -> repository variable. Returns a list of problems."""
    problems = []
    for repo in repos:
        r = gh(["secret", "set", key_name, "-R", repo], stdin=app["pem"])
        if r.returncode: problems.append(f"secret in {repo}: {r.stderr.strip()[:120]}")
        r = gh(["variable", "set", id_name, "-R", repo, "--body", str(app["id"])])
        if r.returncode: problems.append(f"variable in {repo}: {r.stderr.strip()[:120]}")
    return problems

def page(manifest, target, state):
    m = json.dumps(manifest).replace("&", "&amp;").replace('"', "&quot;")
    return (f'<!doctype html><meta charset=utf-8><title>Create {manifest["name"]}</title>'
            f'<body style="font:16px system-ui;max-width:40em;margin:3em auto"><h2>Create the GitHub App "{manifest["name"]}"</h2>'
            f'<p>GitHub will show the app\'s name and permissions. Click <b>Create GitHub App</b> there to continue.</p>'
            f'<form id=f method=post action="{target}?state={state}"><input type=hidden name=manifest value="{m}">'
            f'<button>Continue to GitHub</button></form><script>document.getElementById("f").submit()</script>')

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--project", required=True); ap.add_argument("--role", required=True)
    ap.add_argument("--owner", required=True); ap.add_argument("--org", action="store_true")
    ap.add_argument("--repos", required=True); ap.add_argument("--port", type=int, default=0)
    ap.add_argument("--harness-url", default=None, help="default: the origin of this harness checkout")
    ap.add_argument("--no-browser", action="store_true"); ap.add_argument("--timeout", type=int, default=600)
    ap.add_argument("--single", action="store_true",
                    help="one shared App for the whole crew: key in CREW_APP_KEY, id in CREW_APP_ID (workflows mint short-lived tokens from it)")
    a = ap.parse_args()
    if not re.fullmatch(r"[a-z0-9-]+", a.role) or not re.fullmatch(r"[A-Za-z0-9_.-]+", a.project):
        sys.exit("crew apps: project and role may only contain letters, digits, dashes, dots and underscores")
    if not a.harness_url:
        try:
            a.harness_url = re.sub(r"\.git$", "", subprocess.run(["git", "-C", os.path.dirname(os.path.abspath(__file__)), "remote", "get-url", "origin"],
                                   capture_output=True, text=True, check=True).stdout.strip())
            a.harness_url = re.sub(r"^git@([^:]+):", r"https://\1/", a.harness_url)
        except Exception: a.harness_url = ""
        if not a.harness_url.startswith("http"): sys.exit("crew apps: cannot tell the harness URL (no git origin): pass --harness-url")
    repos = [r for r in a.repos.split(",") if r]
    state = os.urandom(8).hex(); result = {}; done = threading.Event()
    target = f"{WEB}/organizations/{a.owner}/settings/apps/new" if a.org else f"{WEB}/settings/apps/new"

    class H(BaseHTTPRequestHandler):
        def log_message(self, *x): pass
        def reply(self, code, body, ctype="text/html"):
            self.send_response(code); self.send_header("Content-Type", ctype); self.end_headers(); self.wfile.write(body.encode())
        def do_GET(self):
            u = urlparse(self.path)
            if u.path == "/":
                return self.reply(200, page(build_manifest(a.project, a.role, srv.server_port, a.harness_url), target, state))
            if u.path == "/callback":
                q = parse_qs(u.query)
                if q.get("state", [""])[0] != state or not q.get("code"):
                    return self.reply(400, "Bad or missing state/code. Start again from the terminal.")
                try: result["app"] = convert(q["code"][0])
                except Exception as e: result["error"] = f"code exchange failed: {e}"
                self.reply(200, "<body style='font:16px system-ui;margin:3em'>Done. Return to the terminal. You can close this tab.")
                done.set(); return
            self.reply(404, "not found")

    srv = HTTPServer(("127.0.0.1", a.port), H)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    url = f"http://127.0.0.1:{srv.server_port}/"
    print(f"OPEN   {url}", flush=True)
    if not a.no_browser: webbrowser.open(url)
    if not done.wait(a.timeout): sys.exit("crew apps: timed out waiting for the GitHub redirect")
    srv.shutdown()
    if "error" in result: sys.exit(f"crew apps: {result['error']}")
    app = result["app"]
    key_name, id_name = ("CREW_APP_KEY", "CREW_APP_ID") if a.single else (f"AGENT_APP_KEY_{env_suffix(a.role)}", f"AGENT_APP_ID_{env_suffix(a.role)}")
    problems = store(key_name, id_name, app, repos)
    print(f"CREATED {app.get('slug')} (id {app.get('id')}) for role {a.role}")
    print(f"INSTALL https://github.com/apps/{app.get('slug')}/installations/new  (choose: {', '.join(repos)})")
    if problems:
        print("WARN   storing failed: " + "; ".join(problems), file=sys.stderr); sys.exit(1)
    print(f"STORED {key_name} (secret) and {id_name} (variable) in: {', '.join(repos)}")

if __name__ == "__main__":
    main()
