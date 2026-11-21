# Runners: where a role runs

A role (lead, worker, pm, ...) runs in one of two places. You can mix them per role.

Fact labels: **vendor-doc** means taken from the vendor's documentation, **observed YYYY-MM** means seen in practice, **unverified** means written from the design and not yet run end to end.

## 1. Actions runner (role-run.yml)

A GitHub Actions job runs the role. `role-run.yml` checks out the harness, the plan repo and each code repo side by side in the workspace, sets `CREW_HARNESS_DIR`, `CREW_PLAN_DIR` and `CREW_CODE_DIR`, and starts `anthropics/claude-code-action@v1` with a stub prompt. The stub tells the agent to read `prompts/common.md`, `prompts/<role>.md` and the plan repo's owner rules, and to follow them. The role key is passed as `AGENT_PERSONA`.

- Start it from a schedule caller (`crew-schedule-worker.yml`, `crew-schedule-lead.yml`, `crew-schedule-pm.yml`) or by hand with `workflow_dispatch`.
- A wake (an issue comment, a failed CI run) can call `role-run.yml` too, with `kind: wake` and the reason in `prompt_extra`. The shipped wake workflow fires routines only; add a caller of your own for this.
- One run per role at a time (a `concurrency` group per role).

Limits:
- A job is capped at 6 hours (vendor-doc). `timeout_minutes` defaults to 120.
- Runner minutes are billed on private repos (vendor-doc); public repos are free for standard runners (vendor-doc).
- No state survives a run. Anything the agent does not push is lost, as in a routine's fresh VM.
- Scheduled runs are best effort: delayed at busy times, and can be dropped (vendor-doc). Scheduled workflows in a public repo are disabled after 60 days without repo activity (vendor-doc).
- Cron is UTC, 5 minutes is the shortest interval (vendor-doc).
- Cloning code repos other than the plan repo uses the crew App token (or `CREW_REPO_TOKEN`); unverified end to end.

## 2. Claude routines runner

A routine is a saved prompt that Claude runs in a cloud session on a schedule, an API call or a GitHub event (see `recipes/routines.md`). The wake workflow fires a role's routine by its API trigger. The trigger id is `roles.<role>.trigger` and the token is the secret named by `roles.<role>.secret` in `crew.json`.

Limits:
- Needs a Claude plan that includes routines, and a daily routine-run cap (see `recipes/cost-and-limits.md`).
- Each run starts a fresh cloud VM with no memory; the schedule is UTC and no more often than hourly (observed 2026-11, per the routines recipe).
- Triggers and tokens are created in the web UI only; the harness cannot create them.
- Routines do not need Actions minutes, only a small job to fire them.

## How the callers are installed

Reusable workflows cannot hold triggers (`issues`, `issue_comment`, `workflow_run`, `schedule` ...). So `crew init` copies the files in `templates/callers/` into `.github/workflows/` and replaces `<HARNESS_REPO>`, `<HARNESS_REF>` and `<PLAN_REPO>`. Each caller holds the triggers and a `uses:` line pointing at a reusable workflow in the harness repo (vendor-doc: `uses: owner/repo/.github/workflows/file.yml@ref`; pin the ref to a tag or sha you trust, because it runs with your secrets).

| Caller | Install in | Calls | Needed for |
|---|---|---|---|
| crew-wake.yml | plan repo and each code repo | wake.yml | routines runner (fires routines) |
| crew-review.yml | each code repo | review.yml | the `merge-ready` check |
| crew-change-sync.yml | plan repo | change-sync.yml | status issues, milestones |
| crew-owner-alert.yml | plan repo | owner-alert.yml | owner @mention fallback |
| crew-schedule-*.yml | plan repo | role-run.yml | Actions runner |

Keep workflow names consistent: the names in `crew-wake.yml` `workflows:` must equal your CI workflow's `name:` and `crew-review`.

Every caller passes `secrets: inherit`, so the called workflow sees the caller repo's secrets (vendor-doc). Permissions of the called job are capped by the caller's `permissions:`, so the callers set them.

## Secrets

| Secret | Needed by | Notes |
|---|---|---|
| `CLAUDE_CODE_OAUTH_TOKEN` | Actions runner, review | Claude Code OAuth token for `claude-code-action`, fetched by `crew init` through `claude setup-token` (never pasted). Not needed for the routines runner alone. |
| `CREW_APP_ID` (variable) + `CREW_APP_KEY` (secret) | all workflows that read another repo | The crew GitHub App, created by `crew apps create --single` (or `crew init`). Workflows mint a short-lived installation token from it at run time. |
| `CREW_REPO_TOKEN` | optional fallback | A fine-grained personal access token, only if you choose `--identity token`. |
| One fire token per routine, named by `roles.<role>.secret` | wake.yml, routines runner only | Created in the web UI per routine. Exported as an env var by name; never printed. |
| `AGENT_APP_KEY_<ROLE>` | optional, Actions runner | A role's GitHub App key so it posts under its own identity. Without it the run uses `CREW_REPO_TOKEN`. |
| `GH_AUTOMATION_TOKEN` | optional, change-sync | Edits the org Project and code PR bodies. Without it change-sync writes labels only. |

Set the secrets at org level to share them across repos.

## Choosing

| | Actions runner | Routines runner |
|---|---|---|
| Cost | runner minutes plus plan usage | plan usage only |
| Wake on events | add a caller | built in via wake.yml |
| Run length | up to 6 hours | per the routines limits |
| Setup | secrets and callers | web UI triggers and tokens |

Start with whichever you already pay for. Both use the same prompts, scripts and plan repo, so a role can move between them without other changes.

## Not verified

The workflows pass `actionlint` and the callers parse after substitution. They have not run on GitHub. In particular unverified: `secrets: inherit` making undeclared secrets visible to `toJSON(secrets)` in `wake.yml` (vendor docs say all secrets are passed; check on first run), cloning extra code repos in `role-run.yml`, and `claude-code-action` in agent mode on `schedule` with an explicit `github_token`.
