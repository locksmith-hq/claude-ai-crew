#!/usr/bin/env python3
"""Get a long-lived Claude Code OAuth token and store it as a repo secret, without the user ever seeing or pasting it.

It runs `claude setup-token` (default; override with CREW_CLAUDE_CMD) inside a pseudo-terminal so its browser
login works, shows the program's output with every token masked, keeps the token only in memory, and pipes it
into `gh secret set CLAUDE_CODE_OAUTH_TOKEN -R <repo>` over stdin for each repo. Nothing is written to disk or
passed as an argument.

Usage: claude_token.py --repos a/b,c/d [--secret NAME]
"""
import argparse, fcntl, os, pty, re, select, shlex, struct, subprocess, sys, termios, webbrowser

TOKEN = re.compile(r"sk-ant-[A-Za-z0-9_-]{20,}")
LOGIN_URL = re.compile(r"https://claude\.(?:com|ai)/[^\s\x1b\x07]*oauth/authorize\?[^\s\x1b\x07]+")

class Screen:
    """A tiny virtual terminal. `claude setup-token` draws a full-screen UI and repaints it with cursor moves and
    erases, so joining the raw output scrambles text (the login URL ended up inside the token). Applying the moves the
    way a terminal does gives the text as it appears on screen. Only the controls that UI uses are handled."""
    def __init__(self):
        self.rows = {}; self.r = 0; self.c = 0; self.osc_urls = []; self._buf = ""; self.tokens = []

    def _put(self, ch):
        line = self.rows.setdefault(self.r, [])
        while len(line) <= self.c: line.append(" ")
        line[self.c] = ch; self.c += 1

    def _erase_line(self, mode):
        line = self.rows.setdefault(self.r, [])
        if mode == 2: self.rows[self.r] = []
        elif mode == 1:
            for i in range(min(self.c + 1, len(line))): line[i] = " "
        else: del line[self.c:]

    def feed(self, data):
        text = self._buf + data.decode("utf-8", "replace"); self._buf = ""; i = 0; n = len(text)
        while i < n:
            ch = text[i]
            if ch == "\x1b":
                if i + 1 >= n: self._buf = text[i:]; break
                nxt = text[i + 1]
                if nxt == "[":
                    m = re.compile(r"[0-9;?<>=]*[ -/]*[@-~]").match(text, i + 2)
                    if not m: self._buf = text[i:]; break
                    self._csi(m.group(0)); i = m.end(); continue
                if nxt == "]":
                    m = re.compile(r"(.*?)(?:\x07|\x1b\\)", re.S).match(text, i + 2)
                    if not m: self._buf = text[i:]; break
                    if m.group(1).startswith("8;"):
                        url = m.group(1).split(";", 2)[-1]
                        if url: self.osc_urls.append(url)
                    i = m.end(); continue
                i += 2 if nxt not in "()" else 3; continue
            if ch == "\r": self.c = 0
            elif ch == "\n": self.r += 1; self.c = 0
            elif ch == "\b": self.c = max(0, self.c - 1)
            elif ch >= " ": self._put(ch)
            i += 1
        for t in TOKEN.findall("\n".join(self.lines())): self.tokens.append(t)

    def _csi(self, seq):
        final = seq[-1]; params = seq[:-1].lstrip("?<>=")
        nums = [int(x) if x.isdigit() else 0 for x in re.split(r"[;:]", params)] if params else []
        a = nums[0] if nums and nums[0] else 1
        if final == "A": self.r = max(0, self.r - a)
        elif final == "B": self.r += a
        elif final == "C": self.c += a
        elif final == "D": self.c = max(0, self.c - a)
        elif final == "G": self.c = max(0, a - 1)
        elif final in "Hf": self.r = max(0, (nums[0] if nums and nums[0] else 1) - 1); self.c = max(0, (nums[1] if len(nums) > 1 and nums[1] else 1) - 1)
        elif final == "K": self._erase_line(nums[0] if nums else 0)
        elif final == "J":
            mode = nums[0] if nums else 0
            if mode == 2 or mode == 3: self.rows = {}
            elif mode == 0:
                self._erase_line(0)
                for k in [k for k in self.rows if k > self.r]: del self.rows[k]

    def lines(self):
        return ["".join(self.rows[k]) for k in sorted(self.rows)]

    def login_url(self):
        for u in self.osc_urls:
            if LOGIN_URL.match(u): return u
        m = LOGIN_URL.search("\n".join(self.lines()))
        return m.group(0) if m else None

    def best_token(self):
        return max(self.tokens, key=len).encode() if self.tokens else None

def run_pty(argv):
    """Run argv in a wide pty, track its screen, open the login URL, pass the user's code through, and return
    (exit code, token bytes or None). The child's output is never echoed."""
    pid, fd = pty.fork()
    if pid == 0:
        os.execvp(argv[0], argv)
    try: fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 50, 1000, 0, 0))
    except OSError: pass
    scr = Screen(); announced = False; stdin_open = sys.stdin.isatty()
    while True:
        rlist = [fd] + ([sys.stdin] if stdin_open else [])
        try: r, _, _ = select.select(rlist, [], [], 0.5)
        except (ValueError, OSError): r = [fd]
        if fd in r:
            try: chunk = os.read(fd, 8192)
            except OSError: chunk = b""
            if not chunk: break
            scr.feed(chunk)
            url = scr.login_url()
            if url and not announced:
                announced = True
                print("\ncrew: open this URL and approve the login (opening your browser now):\n  " + url, flush=True)
                try: webbrowser.open(url)
                except Exception: pass
                print("crew: if the page shows a code, paste it here and press Enter. Otherwise just wait.", flush=True)
        if stdin_open and sys.stdin in r:
            line = sys.stdin.readline()
            if line == "": stdin_open = False
            else: os.write(fd, line.rstrip("\r\n").encode() + b"\r")
    _, status = os.waitpid(pid, 0)
    return os.waitstatus_to_exitcode(status), scr.best_token()

MIN_LEN = 90  # real tokens are about 100+ characters; a shorter match is a truncated capture

def verify(token, secret):
    """Check the credential really works before storing it. Uses `claude -p` (override with CREW_VERIFY_CMD).
    Returns (ok, message). Skipped (ok) if the command is not installed."""
    cmd = shlex.split(os.environ.get("CREW_VERIFY_CMD", "claude -p ok --max-turns 1"))
    if subprocess.run(["sh", "-c", f"command -v {shlex.quote(cmd[0])} >/dev/null"]).returncode:
        return True, "claude CLI not found: skipped the check"
    env = dict(os.environ); env.pop("ANTHROPIC_API_KEY", None); env.pop("CLAUDE_CODE_OAUTH_TOKEN", None)
    env["ANTHROPIC_API_KEY" if secret == "ANTHROPIC_API_KEY" else "CLAUDE_CODE_OAUTH_TOKEN"] = token.decode()
    try: r = subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=90, stdin=subprocess.DEVNULL)
    except subprocess.TimeoutExpired: return False, "the check timed out"
    return (r.returncode == 0), ("ok" if r.returncode == 0 else (r.stderr or r.stdout).strip()[-160:])

def already_set(secret, repos):
    """True when every repo already has a Claude credential (the secret, or the other kind), so a re-run needs no login."""
    for repo in repos:
        r = subprocess.run(["gh", "secret", "list", "-R", repo, "--json", "name", "--jq", ".[].name"], capture_output=True, text=True)
        have = set(r.stdout.split())
        if r.returncode or not ({secret, "ANTHROPIC_API_KEY", "CLAUDE_CODE_OAUTH_TOKEN"} & have): return False
    return True

def store_all(secret, value, repos):
    failed = []
    for repo in repos:
        r = subprocess.run(["gh", "secret", "set", secret, "-R", repo], input=value, capture_output=True)
        if r.returncode: failed.append(f"{repo}: {r.stderr.decode()[:100].strip()}")
        else: print(f"STORED {secret} in {repo}", flush=True)
    if failed: sys.exit("crew: failed to store the secret: " + "; ".join(failed))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repos", required=True); ap.add_argument("--secret", default="CLAUDE_CODE_OAUTH_TOKEN")
    ap.add_argument("--force", action="store_true", help="store a new credential even if the secret already exists")
    ap.add_argument("--no-web", action="store_true", help="never start a browser login; fail if no token or key is in the environment")
    a = ap.parse_args()
    repos = [r for r in a.repos.split(",") if r]
    # Non-web sources first: a token or an API key already in the environment (no browser, nothing pasted).
    for env, secret in (("CLAUDE_CODE_OAUTH_TOKEN", "CLAUDE_CODE_OAUTH_TOKEN"), ("ANTHROPIC_API_KEY", "ANTHROPIC_API_KEY")):
        val = os.environ.get(env, "").strip()
        if val:
            print(f"crew: using {env} from the environment (no login needed).", flush=True)
            ok, msg = verify(val.encode(), secret)
            if not ok: sys.exit(f"crew: {env} from the environment does not work ({msg}); nothing was stored.")
            store_all(secret, val.encode(), repos); return
    if not a.force and already_set(a.secret, repos):
        print(f"crew: {a.secret} is already set in every repo; nothing to do (use --force to replace it).", flush=True); return
    if a.no_web:
        sys.exit("crew: no CLAUDE_CODE_OAUTH_TOKEN or ANTHROPIC_API_KEY in the environment and --no-web was given.")
    argv = shlex.split(os.environ.get("CREW_CLAUDE_CMD", "claude setup-token"))
    print("crew: running `%s` (its screen is not shown; the token is never displayed)." % " ".join(argv), flush=True)
    code, token = run_pty(argv)
    if token is not None and len(token) < MIN_LEN:  # token is bytes here
        sys.exit("crew: the captured token is too short (%d characters), so it was truncated; nothing was stored. "
                 "Run again, or export CLAUDE_CODE_OAUTH_TOKEN and re-run." % len(token))
    if code != 0 or not token:
        sys.exit("crew: could not get a token from `%s` (exit %s). Run `gh secret set %s -R <repo>` yourself, "
                 "or run `claude setup-token` and set the secret by hand." % (" ".join(argv), code, a.secret))
    ok, msg = verify(token, a.secret)
    if not ok: sys.exit(f"crew: the captured token does not work ({msg}); nothing was stored. Run again with --force, or export CLAUDE_CODE_OAUTH_TOKEN.")
    store_all(a.secret, token, repos)

if __name__ == "__main__":
    main()
