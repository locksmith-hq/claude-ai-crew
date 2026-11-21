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
1. **Gather.** Ask once: project name, plan repo (`owner/name`, private), code repo(s), runner (`actions` default, or `routines`), identity (`solo` default, or `apps`). Check `gh auth status` and that `jq`, `git` and `python3` exist.
2. **Dry run.** `scripts/crew init --plan ...` (from the harness checkout). Show the plan in plain words and wait for a yes.
3. **Init.** Run the same command without `--plan`. It creates the plan repo and domain pack, the labels, and an install PR in each repo. Report each `FAIL` line.
4. **Run it.** `crew init` (no `--plan`) creates the repos' files, labels and install PRs, then runs `claude setup-token`: tell the user to approve the Claude login in their browser; the token goes straight into the secrets and is never shown. Do not ask for or accept a pasted token.
5. **GitHub App.** `init` then runs `crew apps create --single`: a browser tab opens. If a browser tool is available, open the printed `OPEN` URL and stop at the page where GitHub shows **Create GitHub App**: the user clicks it. Then open the printed `INSTALL` link; the user chooses the repos and confirms.
6. **Activate.** Show each install PR's files (only `.github/workflows/crew-*.yml`), ask, then `crew activate --crew <plan>/crew.json`: it merges them, enables the schedules and runs doctor.
7. **Verify.** `crew doctor` runs inside activate; fix every `FAIL` and explain each `WARN` with its command.
8. **Hand over.** Summarize what exists, what the user still must do (schedules to enable, first run), and where the docs are (`docs/setup.md`, `docs/runners.md`).

## Repair mode
For a broken setup, start at step 7, fix what doctor flags, and re-run it. Confirm before re-running `init` on an existing plan repo.

## Gotchas
- App names are unique across GitHub: if the name is taken, ask for a different project name and retry that role.
- One App installation must cover the plan and code repos, so they need the same owner; otherwise suggest `solo` (per-repo tokens are not built yet).
- Free GitHub plans cannot require status checks on private repos: the review runs, but nothing blocks a merge.
