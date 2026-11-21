---
name: crew-setup
description: Set up claude-ai-crew for a project end to end: domain pack, plan repo, labels, workflow callers, secrets and per-role GitHub Apps. Use when the user asks to set up, install or configure the crew, or to check or repair an existing setup.
---

# Crew setup

You run `scripts/crew` for the user and drive the browser for the clicks. Dry-run first, ask before each step that creates something, and stop at anything only the human can do.

## Never
- Print, log or ask for a secret value. The user types secrets only into `gh secret set` or the vendor's own page.
- Enter passwords, MFA codes or one-time tokens, or complete a CAPTCHA.
- Create a GitHub App, repo or secret without the user's yes for that step.

## Steps
1. **Gather.** Ask once: project name, plan repo (`owner/name`, private), code repo(s), runner (`actions` default, or `routines`), identity (`solo` default, or `apps`). Check `gh auth status` and that `jq`, `git` and `python3` exist.
2. **Dry run.** `scripts/crew init --plan ...` (from the harness checkout). Show the plan in plain words and wait for a yes.
3. **Init.** Run the same command without `--plan`. It creates the plan repo and domain pack, the labels, and an install PR in each repo. Report each `FAIL` line.
4. **Secrets.** For each repo it names, tell the user to run `gh secret set CLAUDE_CODE_OAUTH_TOKEN -R <repo>` (token from `claude setup-token`) and `gh secret set CREW_REPO_TOKEN -R <repo>` (a fine-grained token with contents, issues and pull requests on all the repos). The user pastes the value at the prompt. You never see it. Wait for "done".
5. **Apps (identity=apps only).** Dry run: `crew apps create --crew <plan>/crew.json --plan`. Ask. Then run it: a browser tab opens per role. If a browser tool is available, open the printed `OPEN` URL, and stop at the page where GitHub shows **Create GitHub App**: the user clicks it. After each role, open the printed `INSTALL` link and have the user choose the listed repos and confirm. Check with `crew apps list`.
6. **Merge the install PRs.** Show each PR's file list (only `.github/workflows/crew-*.yml`) and ask before merging.
7. **Verify.** `crew doctor <plan>/crew.json`. Fix every `FAIL`; for each `WARN`, give the command that clears it.
8. **Hand over.** Summarize what exists, what the user still must do (schedules to enable, first run), and where the docs are (`docs/setup.md`, `docs/runners.md`).

## Repair mode
For a broken setup, start at step 7, fix what doctor flags, and re-run it. Confirm before re-running `init` on an existing plan repo.

## Gotchas
- App names are unique across GitHub: if the name is taken, ask for a different project name and retry that role.
- One App installation must cover the plan and code repos, so they need the same owner; otherwise suggest `solo` (per-repo tokens are not built yet).
- Free GitHub plans cannot require status checks on private repos: the review runs, but nothing blocks a merge.
