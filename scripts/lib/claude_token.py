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

def mask_lines(state, chunk):
    """Line-based masking that survives a token being wrapped across lines by the terminal.
    state = {"partial": bytes, "hiding": bool}. Returns bytes that are safe to show.
    A line containing a token (or its prefix) is replaced, and the lines that follow up to the next blank line
    are hidden too, because the terminal may have wrapped the rest of the token onto them."""
    out = []
    data = state["partial"] + chunk
    *lines, state["partial"] = data.split(b"\n")
    for line in lines:
        plain = re.sub(rb"\x1b\[[0-9;?]*[A-Za-z]|\r", b"", line)
        if state["hiding"]:
            if plain.strip() == b"": state["hiding"] = False; out.append(line + b"\n")
            continue
        if TOKEN.search(plain) or b"sk-ant-" in plain:
            out.append(b"<token hidden>\n"); state["hiding"] = True
        else:
            out.append(line + b"\n")
    return b"".join(out)

def flush_partial(state):
    """Show an unfinished line (a prompt) only if it cannot contain a token."""
    p = state["partial"]
    if p and not state["hiding"] and b"sk-ant" not in p and not TOKEN.search(p):
        state["partial"] = b""; return p
    return b""

def run_pty(argv):
    """Run argv in a pty, echo masked output, return (exit code, token bytes or None)."""
    pid, fd = pty.fork()
    if pid == 0:
        os.execvp(argv[0], argv)
    buf = b""; token = None; state = {"partial": b"", "hiding": False}
    stdin_open = sys.stdin.isatty()
    while True:
        rlist = [fd] + ([sys.stdin] if stdin_open else [])
        try: r, _, _ = select.select(rlist, [], [], 0.5)
        except (ValueError, OSError): r = [fd]
        if not r:
            sys.stdout.buffer.write(flush_partial(state)); sys.stdout.buffer.flush()
        if fd in r:
            try: chunk = os.read(fd, 4096)
            except OSError: chunk = b""
            if not chunk: break
            buf += chunk
            sys.stdout.buffer.write(mask_lines(state, chunk)); sys.stdout.buffer.flush()
        if stdin_open and sys.stdin in r:
            data = os.read(sys.stdin.fileno(), 1024)
            if data: os.write(fd, data)
    _, status = os.waitpid(pid, 0)
    code = os.waitstatus_to_exitcode(status)
    sys.stdout.buffer.write(flush_partial(state)); sys.stdout.buffer.flush()
    # The token may have been wrapped across lines by the terminal: search the whole output without breaks or escapes.
    flat = re.sub(rb"\x1b\[[0-9;?]*[A-Za-z]|[\r\n]", b"", buf)
    m = TOKEN.search(flat)
    if m: token = m.group(0)
    return code, token

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
    ap.add_argument("--no-web", action="store_true", help="never start a browser login; fail if no token or key is in the environment")
    a = ap.parse_args()
    repos = [r for r in a.repos.split(",") if r]
    # Non-web sources first: a token or an API key already in the environment (no browser, nothing pasted).
    for env, secret in (("CLAUDE_CODE_OAUTH_TOKEN", "CLAUDE_CODE_OAUTH_TOKEN"), ("ANTHROPIC_API_KEY", "ANTHROPIC_API_KEY")):
        val = os.environ.get(env, "").strip()
        if val:
            print(f"crew: using {env} from the environment (no login needed).", flush=True)
            store_all(secret, val.encode(), repos); return
    if a.no_web:
        sys.exit("crew: no CLAUDE_CODE_OAUTH_TOKEN or ANTHROPIC_API_KEY in the environment and --no-web was given.")
    argv = shlex.split(os.environ.get("CREW_CLAUDE_CMD", "claude setup-token"))
    print("crew: running `%s`. Approve the login in your browser; the token is never shown." % " ".join(argv), flush=True)
    code, token = run_pty(argv)
    if code != 0 or not token:
        sys.exit("crew: could not get a token from `%s` (exit %s). Run `gh secret set %s -R <repo>` yourself, "
                 "or run `claude setup-token` and set the secret by hand." % (" ".join(argv), code, a.secret))
    store_all(a.secret, token, repos)

if __name__ == "__main__":
    main()
