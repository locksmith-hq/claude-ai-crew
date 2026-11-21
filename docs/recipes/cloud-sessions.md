# Cloud sessions

A Claude Code cloud session is a throwaway Linux VM that runs your agent with your repo checked out; this page lists what it gives you, its limits, and the gotchas seen in real runs.

Facts marked "docs" come from the vendor's Claude Code docs (fetched 2026-11) and were not all re-tested. Facts marked "observed" happened in real runs.

## What a session gives you
- **Machine (docs, 2026-11):** Ubuntu 24.04 VM, about 4 vCPU, 16 GB RAM, 30 GB disk. It pauses when idle and is thrown away later.
- **Anything not pushed is lost** when the session ends. Make "never leave the VM with unpushed work" a hard rule (see `run-lifecycle.md`).
- **Preinstalled (docs, 2026-11):** docker, dockerd, docker compose, Rust, Node 20 to 22, Python, gcc/clang. A system Postgres is installed; pin your own version in compose if you need another.
- **Repo config that is honoured:** `CLAUDE.md`, `.claude/settings.json` (hooks, permissions), `.mcp.json`, skills, agents. A SessionStart hook runs when `CLAUDE_CODE_REMOTE=true`.
- **Ignored in the cloud:** `~/.claude`, local plugins, user-scope MCP servers. Put everything an agent needs in the repo.
- **Command time limits (docs, 2026-11):** 2 min by default, up to 10 min on request, then backgrounded for up to 30 min. Raise them with `BASH_DEFAULT_TIMEOUT_MS` and `BASH_MAX_TIMEOUT_MS`.
- **Usage:** a cloud run cannot read the plan's usage numbers (the usage tool exists only in the desktop app, observed 2026-11). Control spend by cadence and model (see `cost-and-limits.md`).
- **Limits on runs (docs, 2026-11):** cron is UTC, no more often than hourly; 100 runs per hour per account.
- **Permission mode:** runs start in auto mode and stop on ask-rule matches (docs, 2026-11).

## Environments
An environment is a named bundle of network policy, environment variables and a setup script. Create one per trust level, not one per task.

- **Network:** choose Limited with "Allow package managers" for code-running roles. That allowlist covers the usual registries (crates, npm, PyPI, Docker Hub, GitHub, apt). Add extra domains only when a role needs them.
- **Separate environments for web access.** A role that reads the open web (research) gets its own environment, so a prompt-injected page cannot reach a session that runs code or holds other keys. Never switch to Full network on a shared environment.
- **Documentation-only hosts:** a research environment can allow specific docs hosts. Treat user-written sites (forums, blogs) as hints: confirm a claim on the registry, the project repo or official docs before acting.
- **Environment variables are readable by the model and by every command it runs.** Put no secrets there unless the owner accepts the risk in writing. If you must (for example a GitHub App key), give each environment only the keys of its own role (see `github-apps-and-identity.md`).
- **Network secrets (docs, 2026-11):** a secret stored as a network secret is attached to outgoing requests by a proxy, so it never enters the VM. It is a fixed header, so it cannot do anything that needs a freshly signed token (a short-lived signed JWT, SigV4 request signing).
- **Setup script:** keep it tiny. Make it find the cloned repo and call a script in the repo, with a built-in fallback if the repo is not there yet. Then changes merge through a PR and apply without re-pasting. Install toolchains, `just`-style runners, test runners and lint tools here.
- **Setup has a time budget.** Observed 2026-11: pre-pulling container images in the setup script blew the roughly 5-minute cache budget and hung a run. Pull images on demand instead.

## Gotchas observed (2026-11, all verified in real runs)
- **Container registry access:** `ghcr.io` returned 403 although the docs list it as allowed. Use Docker Hub images in compose files, with the image name overridable by an environment variable.
- **Docker daemon:** `service docker start` failed in the VM. Starting `dockerd &` in the background worked. Start it from a SessionStart hook (remote only, no image pulls) so the daemon is ready when the agent first needs it. A preflight script can start it as a fallback.
- **Running as root:** the VM runs as root. Root-only differences exist (for example, root bypasses process-memory protections, so a test that asserts "another process cannot read memory" fails). Make such tests skip when uid is 0 and let a non-root CI runner cover them.
- **Dependencies missing:** a web test job failed until `npm ci` had run. Run it in the background in preflight (see `run-lifecycle.md`, long commands).
- **GraphQL blocked:** the session's GitHub proxy rejected GraphQL calls, so `gh pr` and `gh issue` fail. REST works through `gh api`. Write skills with `gh api repos/<org>/<repo>/...` commands.
- **GitHub token:** `GITHUB_TOKEN` is a placeholder; real auth goes through the proxy with the connected identity.
- **Job logs blocked:** CI job logs were not readable through the proxy. Read check-run annotations (`gh api .../check-runs/<id>/annotations`) instead.
- **App token requests refused:** the session proxy refused GitHub App token requests with 403 (observed 2026-11). See `github-apps-and-identity.md` for the workaround and its trade-off.
- **A tool wrapped in `docker run -i` can hang** and a plain TERM does not stop the docker client. Wrap it as `timeout -s KILL <s> docker run -i --rm --init --name <n> ...` and run `docker rm -f <n>` after. Check the image's `--help` for its transport flag first (one MCP server image defaulted to SSE and hung a stdio run for 300 s).
- **Foreground `sleep` was blocked.** Wait on state (a log, a file, `until` loop under a timeout) instead of time.
- **Subagents run async in the cloud.** The turn must end with a status line and the hand-back resumes the agent. Never end a turn while only a background job runs: poll it.

## Branch protection
Branch protection on a private repo needed a paid GitHub plan (observed 2026-11: the API returned 403 on a free org). Until the repo is public or the plan is upgraded, only the prompt keeps runs off the default branch. Decide this explicitly and record it.

## Sources of truth
Vendor docs for cloud sessions, environments and routines (code.claude.com docs). Re-check them before relying on a "docs" fact.
