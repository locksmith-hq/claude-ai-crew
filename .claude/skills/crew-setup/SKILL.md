---
name: crew-setup
description: Set up claude-ai-crew for a project end to end: domain pack, plan repo, labels, workflow callers, secrets and per-role GitHub Apps. Use when the user asks to set up, install or configure the crew, or to check or repair an existing setup.
---

# Crew setup

You run `scripts/crew` for the user and drive the browser for the clicks. Dry-run first, ask before each step that creates something, and stop at anything only the human can do.

## Never
- Print, log or ask for a secret value. Secrets move only through the CLI's own pipes (Claude login, App creation).
- Enter passwords, MFA codes or one-time tokens, or complete a CAPTCHA.
- Create a GitHub App, repo or secret without the user's yes for that step.

## Steps
1. **Gather.** Ask once: project name, plan repo (`owner/name`, private), code repo(s), runner (`actions` default, or `routines`), identity (`gh` default, no web; `app` or `roles` need GitHub clicks). Check `gh auth status` and that `jq`, `git`, `python3` exist. Ask whether `CLAUDE_CODE_OAUTH_TOKEN` or `ANTHROPIC_API_KEY` is exported in the terminal you will use.
2. **Dry run.** `scripts/crew init --plan ...` (from the harness checkout). Explain the plan in plain words and wait for a yes.
3. **Run it** in the user's Terminal panel (not in the background: the browser fallback needs a real terminal): `scripts/crew init ...`. It creates the repo files, labels and install PRs, stores the Claude credential and the repo-access token by pipe, merges the install PRs and enables the schedules. Report each `FAIL` line.
4. **Fallbacks.** No Claude credential in the environment: the login opens a browser; the user approves it (and pastes the one-time code if asked). With `--identity app|roles`, GitHub shows **Create GitHub App** and **Install** pages: with the user's yes, drive them (open the printed `OPEN` URL, click create, then the `INSTALL` link; choose only the crew repos).
5. **Verify.** `scripts/crew doctor <plan>/crew.json`: fix every `FAIL`; for each `WARN`, give the command that clears it.
6. **Hand over.** Summarize what exists and where the docs are (`docs/setup.md`, `docs/runners.md`).

## Repair mode
For a broken setup, start at step 7, fix what doctor flags, and re-run it. Confirm before re-running `init` on an existing plan repo.

## Gotchas
- App names are unique across GitHub: if the name is taken, ask for a different project name and retry that role.
- One App installation must cover the plan and code repos, so they need the same owner; otherwise suggest `solo` (per-repo tokens are not built yet).
- Free GitHub plans cannot require status checks on private repos: the review runs, but nothing blocks a merge.
