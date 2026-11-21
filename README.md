# claude-ai-crew

A reusable harness for running a **team of scheduled Claude Code agents** on any software project.
It holds the roles, prompts, skills, routing rules, scripts and the hard-won recipes. Your project
supplies a small **domain pack** (a config file plus your own rules and plan); the crew does the rest.

> Status: foundation. Role prompts, the domain-pack schema and the recipes are here.
> Skills, scripts and reusable workflows are being moved in over the next releases (see the roadmap below).

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

1. Fork or clone this repo (or use it as a template).
2. Create a **plan repo** (private is fine) and add a `crew.json` (see [docs/domain-pack.md](docs/domain-pack.md) and [examples/domain-pack](examples/domain-pack)).
3. Create one GitHub App per role (see [docs/recipes/github-apps-and-identity.md](docs/recipes/github-apps-and-identity.md)).
4. Create the routines (see [docs/recipes/routines.md](docs/recipes/routines.md)). Start with one worker and one lead.
5. Read [docs/concepts.md](docs/concepts.md) for the trust model before giving agents any permissions.

## Docs

- [docs/concepts.md](docs/concepts.md): roles, channels, the run lifecycle, the trust model.
- [docs/domain-pack.md](docs/domain-pack.md): what your project provides and the `crew.json` schema.
- [docs/recipes/](docs/recipes): what we learned running this in practice (cloud sessions, routines, apps, merge policy, costs).
- [prompts/](prompts): generic role prompts and the shared rules.

## Roadmap

1. Foundation (this release): README, concepts, domain-pack schema, role prompts, recipes.
2. Skills and scripts with their tests, made config-driven.
3. Reusable GitHub workflows (wake-agents, review, change sync).
4. A `crew doctor` check that validates a domain pack and a project's wiring.

## Safety

The harness is built around one rule: **only the owner and the files they control instruct the agents.**
Everything else (comments, CI logs, web pages, READMEs) is data. Read [docs/concepts.md](docs/concepts.md).
Never put secrets in any repo; see [SECURITY.md](SECURITY.md).

## License

Apache-2.0. See [LICENSE](LICENSE).
