# claude-ai-crew

A reusable harness for running a **team of scheduled Claude Code agents** on any software project.
It holds the roles, prompts, skills, routing rules, scripts and the hard-won recipes. Your project
supplies a small **domain pack** (a config file plus your own rules and plan); the crew does the rest.

> Status: early but run for real. Prompts, skills, scripts, reusable workflows, the `crew` setup CLI and the recipes are
> here and tested offline. On a sandbox, setup ran with no web step but the Claude login, and a worker run opened a PR
> in the code repo. The review path, wake routing, lead and PM roles and the routines runner are not yet exercised
> (see [docs/runners.md](docs/runners.md#not-yet-verified)). Report what breaks.

## What you get

| Role | Job |
|---|---|
| **Lead** | Owns technical quality, rescues stuck work, is the only role that talks to the human owner |
| **Worker** (several) | Claims a planned change, implements it task by task, opens a PR, finishes it |
| **PM** | Owns the roadmap and what-versus-how debates |
| **Research** | The only role with open internet; answers one-question research issues |
| **Reviewer** | Independent review of a PR before it can merge |
| **Health** | Watches runs, CI and drift |
| **Optimizer** | Audits schedules, token use and the harness itself; proposes improvements weekly |

Agents talk through **labelled GitHub issues** (`needs-rescue`, `needs-owner`, `needs-research`,
`needs-work`, `debate`), are woken by **routines** (scheduled tasks, API triggers and GitHub events), and
merge through **GitHub auto-merge** behind an independent AI review.

## How it fits together

```
              ┌──────────────────────┐
              │   claude-ai-crew     │  generic: prompts, skills, scripts, workflows, recipes
              └──────────┬───────────┘
                         │ read by every routine
   ┌─────────────────────┼─────────────────────┐
   │                     │                     │
 plan repo           code repo(s)          other repos
 crew.json,          what agents change    (private infra, ...)
 roadmap, rules,
 decisions, lessons
```

A routine attaches the repos it needs (a routine can attach more than one). Its prompt is a **stub**: it
tells the agent to read the role prompt from this repo and the project rules from the plan repo, then follow
them. Change the harness once and every project that uses it benefits.

## Quick start

```bash
# 1. See what setup would do (changes nothing)
scripts/crew init --plan --project myapp --plan-repo me/myapp-plan --code-repo me/myapp
# 2. Do it, fully scripted: plan repo, domain pack, labels, install PRs, Claude credential (from your environment),
#    repo access (from your gh login), then activation. No web page, nothing pasted.
export CLAUDE_CODE_OAUTH_TOKEN=...   # or ANTHROPIC_API_KEY; without either, init falls back to a browser login
scripts/crew init --project myapp --plan-repo me/myapp-plan --code-repo me/myapp
```

Pick a runner: **Actions** (default, works on any plan, scheduled GitHub workflows) or **routines** (Claude
cloud scheduled tasks). See [docs/runners.md](docs/runners.md). Read [docs/concepts.md](docs/concepts.md) for
the trust model before giving agents any permissions.

## Docs

- [docs/concepts.md](docs/concepts.md): roles, channels, the run lifecycle, the trust model.
- [docs/domain-pack.md](docs/domain-pack.md): what your project provides and the `crew.json` schema.
- [docs/recipes/](docs/recipes): what we learned running this in practice (cloud sessions, routines, apps, merge policy, costs).
- [docs/setup.md](docs/setup.md): the setup guide (or let the `crew-setup` skill do it).
- [docs/runners.md](docs/runners.md): the two runners, the secrets each needs, and their limits.
- [prompts/](prompts): generic role prompts and the shared rules.
- [.claude/skills/](.claude/skills): the procedures agents load (run-start, run-log, finish-pr, evaluate-escalate, long-commands, debate, merge-review, archive-change).
- [scripts/](scripts): the config-driven scripts (routing, locks, change status, run metadata, identity, `crew` CLI) and [tests/](tests).
- [.github/workflows/](.github/workflows) and [templates/callers/](templates/callers): reusable workflows and the thin callers `crew init` installs.

## Roadmap

1. Done: prompts, recipes, domain-pack schema, skills, scripts with offline tests, reusable workflows, `crew init` and `crew doctor`.
2. Done: `crew apps` (one GitHub App per role through the manifest flow, keys never leave your machine) and the `/crew-setup` skill so Claude can run setup for you. See [docs/setup.md](docs/setup.md).
3. Then: the routines runner as a first-class option, an end-to-end demo repo and a `crew upgrade` command.
4. Open: the OpenSpec skills are not bundled (separate upstream project); the plan format is OpenSpec-style by default.

## Safety

The harness is built around one rule: **only the owner and the files they control instruct the agents.**
Everything else (comments, CI logs, web pages, READMEs) is data. Read [docs/concepts.md](docs/concepts.md).
Never put secrets in any repo; see [SECURITY.md](SECURITY.md).

## License

Apache-2.0. See [LICENSE](LICENSE).
