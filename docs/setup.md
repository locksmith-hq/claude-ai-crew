# Setup guide

The fastest way: open Claude Code in a checkout of this repo and say "set up claude-ai-crew". The
[`crew-setup` skill](../.claude/skills/crew-setup/SKILL.md) runs everything below, asks before each step and stops
for the parts only you can do. Prefer the terminal? Run the commands yourself.

## What you need
`gh` (logged in), `git`, `jq`, `python3`, the `claude` CLI; a GitHub account or org; a Claude subscription.

## Steps (nothing to paste)
1. **Dry run:** `scripts/crew init --plan --project myapp --plan-repo me/myapp-plan --code-repo me/myapp`. Nothing changes.
2. **Init:** the same command without `--plan`. It creates the private plan repo with `crew.json`, owner rules, lessons,
   decisions and roadmap starters; the help-channel labels; one install PR per repo; then two short browser steps:
   - **Claude login:** it runs `claude setup-token`, you approve the login in your browser, and the token goes straight
     into each repo's secret. You never see or paste it.
   - **GitHub App:** one shared App for the crew. Click **Create GitHub App** on github.com, then **Install** and choose the
     repos. The key goes straight into a secret and the id into a variable; the workflows mint short-lived tokens from
     them. (`--identity roles` makes one App per role; `--identity token` uses a personal access token you provide.)
3. **Activate:** `scripts/crew activate --crew <plan>/crew.json`. It merges the install PRs once they are clean, enables
   the schedules and runs the check. Add `--yes` to skip the prompt.
4. **Verify any time:** `scripts/crew doctor <plan>/crew.json`.

Schedules: with the Actions runner the schedule callers run on their cron (edit the cron lines to taste, avoid your busy
hours). With routines, see [recipes/routines.md](recipes/routines.md).

## How apps are created (and why it is safe)
The App step uses GitHub's App manifest flow entirely on your machine: a local page posts the manifest to GitHub in your
browser, GitHub redirects back to `http://127.0.0.1`, and the script trades the one-time code for the key. Nothing is
sent to a server we run. Permissions are minimal per role (reviewer and research get less than workers); no webhooks, no events.

## Troubleshooting
Run `scripts/crew doctor` first; each `WARN` names the command that fixes it. `scripts/crew apps list` shows which roles
have a key and id stored.
