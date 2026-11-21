# Setup guide

The fastest way: open Claude Code in a checkout of this repo and say "set up claude-ai-crew". The
[`crew-setup` skill](../.claude/skills/crew-setup/SKILL.md) runs everything below, asks before each step and stops
for the parts only you can do. Prefer the terminal? Run the commands yourself.

## What you need
`gh` (logged in), `git`, `jq`, `python3`; a GitHub account or org; a Claude subscription (for `claude setup-token`).

## Steps
1. **Dry run:** `scripts/crew init --plan --project myapp --plan-repo me/myapp-plan --code-repo me/myapp`. Nothing changes.
2. **Init:** the same command without `--plan`. Creates the private plan repo with `crew.json`, owner rules, lessons,
   decisions and roadmap starters; the help-channel labels; and one PR per repo installing the workflow callers.
3. **Secrets** (per repo, you paste the value at the prompt, nothing is shown):
   - `gh secret set CLAUDE_CODE_OAUTH_TOKEN -R <repo>`: a token from `claude setup-token`.
   - `gh secret set CREW_REPO_TOKEN -R <repo>`: a fine-grained token with contents, issues and pull requests on all the repos.
4. **Identity.** Default `solo`: agents act through the workflow token and mark their comments with a role. For a separate
   identity per role (`--identity apps`): `scripts/crew apps create --crew <plan>/crew.json`. For each role a tab opens on
   github.com; click **Create GitHub App**. The key is piped straight into a repo secret; the app id becomes a variable.
   Then open the printed install link and choose the plan and code repos.
5. **Merge the install PRs**, then **verify:** `scripts/crew doctor <plan>/crew.json`.
6. **Schedules:** with the Actions runner the schedule callers run on their cron (edit the cron lines to taste, avoid your
   busy hours). With routines, see [recipes/routines.md](recipes/routines.md).

## How apps are created (and why it is safe)
`crew apps` uses GitHub's App manifest flow entirely on your machine: a local page posts the manifest to GitHub in your
browser, GitHub redirects back to `http://127.0.0.1`, and the script trades the one-time code for the key. Nothing is
sent to a server we run. Permissions are minimal per role (reviewer and research get less than workers); no webhooks, no events.

## Troubleshooting
Run `scripts/crew doctor` first; each `WARN` names the command that fixes it. `scripts/crew apps list` shows which roles
have a key and id stored.
