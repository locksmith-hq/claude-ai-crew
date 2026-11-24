# Setup guide

The fastest way: open Claude Code in a checkout of this repo and say "set up claude-ai-crew". The
[`crew-setup` skill](../.claude/skills/crew-setup/SKILL.md) runs everything below, asks before each step and stops
for the parts only you can do. Prefer the terminal? Run the commands yourself.

## What you need
`gh` (logged in), `git`, `jq`, `python3`, the `claude` CLI; a GitHub account or org; a Claude subscription.

## Steps (fully scripted: no web page, nothing pasted)
1. **Dry run:** `scripts/crew init --plan --project myapp --plan-repo me/myapp-plan --code-repo me/myapp`. Nothing changes.
2. **Init:** the same command without `--plan`. It does everything:
   - creates the private plan repo with `crew.json` (the roles: lead, pm, research and `--workers N` workers, default 2), owner rules, lessons, decisions and roadmap starters, the help labels, and an install PR per repo that includes **one generated schedule per role**;
   - stores the **Claude credential** from your environment: `CLAUDE_CODE_OAUTH_TOKEN`, or `ANTHROPIC_API_KEY` (an API key instead of a subscription token). Export one first for a fully web-free run. If neither is set it falls back to `claude setup-token`, which opens a browser; pass `--no-web` to forbid that;
   - stores **repo access** from your `gh` login: `gh auth token | gh secret set CREW_REPO_TOKEN`. It is piped, never shown. If your login lacks the `repo` scope it runs `gh auth refresh`;
   - **activates**: merges the install PRs once clean, enables the schedules and runs the check. `--no-activate` leaves that for `crew activate`.
3. **Verify any time:** `scripts/crew doctor <plan>/crew.json`.

**Identity.** With `--identity gh` (the default) the workflows and agents act as you, using your login token, so comments carry a role marker. It is the only mode with no web step at all. The tradeoff: a long-lived token with your access sits in the repo secrets, so prefer a dedicated machine user or a GitHub App for a team: `--identity app` (one shared App) or `--identity roles` (one per role). GitHub only allows an App to be created and installed with a click on github.com, so those modes need the browser (the `crew-setup` skill can click for you).

## Fire tokens (routines runner)

`crew tokens sync [--crew crew.json] [--dry-run]` sets every role's fire token (`roles.<role>.secret`) as a repo secret in the plan and code repos (`--repo ORG/NAME` adds more), all or nothing: it gathers every value (env var of the same name, else a silent prompt), checks every repo accepts writes, writes, and rolls back on any failure. Values are never printed. For AWS SSM as the source of truth use `--store ssm --ssm-prefix /crew/<project> --region <r>`; nothing assumes AWS by default.

## Schedules

`crew init` generates every role's schedule from `crew.json`; nothing is hand-edited. Workers run about every 90 minutes, staggered and never on weekdays during `schedules.avoid_hours_utc`; the lead runs four times a day, the PM and health once a day, the optimizer weekly; research and the reviewer run on demand. Minutes avoid :00 and :30.

To change them, edit `schedules` in `crew.json` (`avoid_hours_utc`, `roles.<role>.cron` or `enabled: false`) and run `crew schedules --crew <plan>/crew.json --apply`: it opens a PR in the plan repo that regenerates the callers, and you merge it. `crew schedules` alone prints the table. For the routines runner it prints the settings to create in Claude's web UI (`--runner routines`).

## What has been verified

A full run on a sandbox (private plan repo plus private code repo in one organization): `crew init` and activation, then a worker run that opened a PR in the code repo as the crew App. The review path, wake routing, the lead and PM roles and the routines runner have not been exercised yet; see [runners.md](runners.md#not-yet-verified).

## Known limits

- The Claude login is the one step that can need your browser (approve it, and paste a one-time code if the page shows one). Export `CLAUDE_CODE_OAUTH_TOKEN` or `ANTHROPIC_API_KEY` to skip it. Every credential is checked with `claude -p` before it is stored.
- With `--identity gh` agents act as you. GitHub Apps need two clicks on github.com (create, install); create the App under the organization that owns the repos.
- On GitHub's free plan, private repos cannot require status checks or use auto-merge, so the review workflow cannot be enforced there.

## GitHub Apps (optional)
The App step uses GitHub's App manifest flow entirely on your machine: a local page posts the manifest to GitHub in your
browser, GitHub redirects back to `http://127.0.0.1`, and the script trades the one-time code for the key. Nothing is
sent to a server we run. Permissions are minimal per role (reviewer and research get less than workers); no webhooks, no events.

## Troubleshooting
Run `scripts/crew doctor` first; each `WARN` names the command that fixes it. `scripts/crew apps list` shows which roles
have a key and id stored.
