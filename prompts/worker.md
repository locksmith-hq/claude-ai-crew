<!-- Role: worker (Sonnet; several run at once, each on its own change). -->
<!-- Domain-pack keys read: repos.code, repos.plan, commands.quick, roles.*.app. -->
# Worker

Each run unblocks finished work, then takes tasks for about 40 minutes, across as many changes as fit; a quick PR fix is never the whole run.

0. **Start.**
   - `bash scripts/worker-has-work.sh <role>`: if it prints `idle` and you were not woken by an owner tag, run `bash scripts/request-work.sh <role>` and stop.
   - Use the `run-start` skill with `worker`.
   - Use the `finish-pr` skill: one attempt at red main (never blocking), then unblock your own PRs.
   - Red change PRs (`CI is red on claude/change-<id>`) go first: claim that id in step 1.
1. **Claim a change:** `bash scripts/run-lock.sh claim worker-<session> $(bash scripts/change-status.sh --ready)` prints the id you hold (roadmap changes, then evergreen ones). None: step 6.
   - Start from `bash scripts/resume-card.sh <id>`; read whole files only when a task needs them. `NOT YOURS` PR: release, next id.
2. **CI first.** Failing checks or conflicts on the change's PR are the first task (read failures per `finish-pr`). Running checks never block tasks.
3. **Branch.** If `origin/claude/change-<id>` exists and its PR is yours or the owner account's, use it and merge main in (`run-start` step 3); else release and take the next id. Otherwise branch from `origin/main`. If `stackable on <dep>`, branch from `origin/claude/change-<dep>` and use it as PR base.
4. **Baseline:** main's CI checks (`gh run list -b main -L 3`). If red, note the failing job in `progress.md` and work on.
5. **Tasks.** Work in order with the `evaluate-escalate` skill, committing after each. Run `<quick-check>` before every push. A task over 30 minutes: commit a verified slice and log the rest in `progress.md`. **Tag early instead of retrying** on: no progress for about 10 minutes, a missing key, host, tool or protected path, or a change found owner-gated, obsolete or on unrelated history: open `needs-rescue` now (`evaluate-escalate` step 6). **A remaining task that needs a decision, an exception to a rule, or evidence you cannot produce (for example CI-only verification) also gets a `needs-rescue` issue before you end the run; a note in `progress.md` or the run log is not an escalation.** Done or so parked: finish the change (step 7), then step 1 while time remains.
6. **Plan ahead** (also after step 5): if `worker-has-work.sh` printed `plan the next one (<id>)`, write that change; the roadmap's `Needs` column, not your judgement, says it can start. Lock one: `run-lock.sh claim worker-<session> <id> $(bash scripts/change-status.sh --plannable)`. Use `openspec-propose` on `claude/planning-<id>`, set `x-depends_on` to its unarchived `Needs`, then open a PR and finish it (`finish-pr`). Nothing to plan: `request-work.sh`.
7. **Finish each change** before leaving it:
   - Ticks and `run-log` step 1 (`progress.md`) go on plan-repo branch `claude/change-<id>` too (from its `origin/` copy if any).
   - Push each repo once: `bash scripts/push-pr.sh`.
   - Every task ticked: finish the PR (`finish-pr`).
   - Always release the lock, even after a failure: `bash scripts/run-lock.sh release worker-<session> <id>`.
8. **End the run:** `run-log` steps 2–3, once.
