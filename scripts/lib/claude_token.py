#!/usr/bin/env python3
"""Get a long-lived Claude Code OAuth token and store it as a repo secret, without the user ever seeing or pasting it.

It runs `claude setup-token` (default; override with CREW_CLAUDE_CMD) inside a pseudo-terminal so its browser
login works, shows the program's output with every token masked, keeps the token only in memory, and pipes it
into `gh secret set CLAUDE_CODE_OAUTH_TOKEN -R <repo>` over stdin for each repo. Nothing is written to disk or
passed as an argument.

Usage: claude_token.py --repos a/b,c/d [--secret NAME]
"""
import argparse, os, pty, re, select, shlex, subprocess, sys

TOKEN = re.compile(rb"sk-ant-[A-Za-z0-9_-]{20,}")

def run_pty(argv):
    """Run argv in a pty, echo masked output, return (exit code, token bytes or None)."""
    pid, fd = pty.fork()
    if pid == 0:
        os.execvp(argv[0], argv)
    buf = b""; token = None
    stdin_open = sys.stdin.isatty()
    while True:
        rlist = [fd] + ([sys.stdin] if stdin_open else [])
        try: r, _, _ = select.select(rlist, [], [], 0.5)
        except (ValueError, OSError): r = [fd]
        if fd in r:
            try: chunk = os.read(fd, 4096)
            except OSError: chunk = b""
            if not chunk: break
            buf += chunk
            m = TOKEN.search(buf)
            if m and token is None: token = m.group(0)
            sys.stdout.buffer.write(TOKEN.sub(b"<token hidden>", chunk)); sys.stdout.buffer.flush()
        if stdin_open and sys.stdin in r:
            data = os.read(sys.stdin.fileno(), 1024)
            if data: os.write(fd, data)
    _, status = os.waitpid(pid, 0)
    code = os.waitstatus_to_exitcode(status)
    # A token split across two reads: search the whole buffer once more.
    if token is None:
        m = TOKEN.search(re.sub(rb"\x1b\[[0-9;]*[A-Za-z]|[\r\n]", b"", buf))
        if m: token = m.group(0)
    return code, token

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repos", required=True); ap.add_argument("--secret", default="CLAUDE_CODE_OAUTH_TOKEN")
    a = ap.parse_args()
    repos = [r for r in a.repos.split(",") if r]
    argv = shlex.split(os.environ.get("CREW_CLAUDE_CMD", "claude setup-token"))
    print("crew: running `%s`. Approve the login in your browser; the token is never shown." % " ".join(argv), flush=True)
    code, token = run_pty(argv)
    if code != 0 or not token:
        sys.exit("crew: could not get a token from `%s` (exit %s). Run `gh secret set %s -R <repo>` yourself, "
                 "or run `claude setup-token` and set the secret by hand." % (" ".join(argv), code, a.secret))
    failed = []
    for repo in repos:
        r = subprocess.run(["gh", "secret", "set", a.secret, "-R", repo], input=token, capture_output=True)
        if r.returncode: failed.append(f"{repo}: {r.stderr.decode()[:100].strip()}")
        else: print(f"STORED {a.secret} in {repo}", flush=True)
    token = None
    if failed: sys.exit("crew: failed to store the secret: " + "; ".join(failed))

if __name__ == "__main__":
    main()
