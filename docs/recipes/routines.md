# Routines (scheduled and triggered agents)

A routine is a saved prompt that Claude runs in a cloud session on a schedule, from an API call, or from a GitHub event; this page covers the trigger types, how to wire them and how to size the cadence.

Facts marked "docs" are from the vendor docs (2026-11). Facts marked "observed" happened in real runs.

## Trigger types
- **Cron (schedule):** UTC, no more often than hourly (docs, 2026-11). It cannot express "every 90 minutes". Observed 2026-11: three routines on the same prompt, offset by minutes (:05, :35, :50), each firing in 2 of every 3 hours, gave a start about every 30 minutes without peaks.
- **API trigger:** an HTTP call with a per-routine bearer token wakes one routine. This is how GitHub Actions wake agents (below). The token is shown once; store it as a repo secret at creation.
- **GitHub-event trigger:** fires on pull request events (docs, 2026-11). Observed 2026-11: set up in the web UI only; one GitHub trigger per routine per repo; filters are clauses such as author, labels, base branch and draft state. Issue comments and CI results are not available as triggers. The API could not list or delete triggers.
- **One routine, several triggers** is allowed (for example cron plus API).

## Per-routine tokens
Each routine that can be woken has its own API token. Keep a table (in `routing.json` or similar) of role, trigger id, and the name of the secret holding its token. A new role needs a token, a secret and a row. Never reuse one token for two roles.

## Waking routines from GitHub Actions
GitHub cannot trigger a routine on an issue comment or a CI result, so a small workflow does it:
1. The workflow listens to `issue_comment`, `issues` (labeled, closed) and `workflow_run` (completed).
2. A cheap `if:` prefilter drops most events before a runner starts (author association, labels, bot logins, a marker in the body).
3. A router script reads a routing file and prints which role to wake. The workflow then calls that routine's API trigger with its secret.
4. The call is only a wake-up. The woken agent re-checks its own state and does nothing if there is nothing to do.
Loop guard: count how often one issue wakes one routine. Three or more is a loop worth investigating.
Mark every agent comment with a marker (for example `<!-- agent -->`) so the prefilter can skip agent-written comments from the human path.

## Multiple repos per routine
A routine can attach one or more GitHub repos; each is cloned at the start of a run (vendor docs, 2026-11).
- **Not documented, test it first:** which repo is the working directory, and whose `CLAUDE.md`, skills and hooks load when several repos are attached. Run a read-only canary routine that prints the working directory and the available skills before you rely on a layout.
- **GitHub-event triggers are per repo.** A routine that must react to events in several repos needs one trigger for each, and the vendor's GitHub App must be installed on each.
- **Branch pushes** default to `claude/`-prefixed branches. Restrict anything stricter with GitHub branch rules or rulesets, not routine settings.
- **Practical rule:** keep the routine prompt a stub that reads instructions from the harness repo, attach the plan repo and the code repo(s), and name which is which in the stub (`<harness-repo>`, `<plan-repo>`, `<code-repo>`).

## Why the prompt is a stub
The routine prompt lives in the vendor UI, outside git review. Keep it to: "Read `<common instructions>` and `<role file>` from the default branch of `<harness-repo>` and follow them." Then:
- instruction changes are normal PRs a human reviews;
- the prompt cannot drift from the repo;
- a guard can cap instruction size and fail any agent branch that edits instructions;
- an optimizer can check that the prompt contradicts nothing.
Put repeatable procedures in skills (`.claude/skills/`), so a run loads only the procedure it uses, and put rules into scripts.

## Cadence design
- **Avoid peak hours** of the plan's shared capacity, where you can. Observed 2026-11: the owner chose weekdays about 15:00 to 21:00 local as peak and kept scheduled routines out of it, then relaxed this for workers once event wake-ups carried most work.
- **Event-driven first, cron as safety net.** Wake agents on review verdicts, failing CI, closed channel issues and owner replies. Keep a slow cron so lost events cannot stall the system. Observed 2026-11: workers started at every 4 h, then three workers at about every 90 min once the backlog was deep.
- **Skip empty passes.** A role that is mostly reactive (a lead) should exit at once when nothing is new, and say so in its log.
- **Several workers at once need locks per unit of work** (see `run-lifecycle.md`).
- **All routines share one plan's usage limits.** More routines means hitting the 5-hour or weekly limit sooner. See `cost-and-limits.md`.

## Rules worth keeping
- Never add, remove, pause or reschedule a routine without the owner's approval. Propose it in a `needs-owner` issue with the numbers.
- Attach only the connectors a role needs (least privilege). Observed 2026-11: only the remote-session connector was kept, others removed on purpose.
- Name routines by role, not by persona.
- Do not hardcode trigger ids in agent instructions; list them at run time.

## Sources of truth
Vendor routines docs; your routing file and the wake workflow header comment.
