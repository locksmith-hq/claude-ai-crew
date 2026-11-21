# Run lifecycle

Every scheduled run follows the same shape: start checks, claim one unit of work, implement and independently evaluate it, escalate one tier on failure, log, push, and never leave the VM with unpushed work.

## 1. Run start (a `run-start` skill and script)
- Run one start script with the run kind (worker, lead, review, health, research) and the persona. It switches to the role's GitHub App identity (see `github-apps-and-identity.md`), then prints one line per check: `OK`, `FIXED`, `WARN`, `FAIL`.
- Checks: container daemon, toolchain, registry reachability, dependencies installed, disk, network.
- Fix every `FAIL` before real work. Record each `WARN`, `FAIL` and `FIXED` (except expected ones, like starting the daemon) as `friction`.
- The script prints the active lessons (cap about 5) and the run reads the owner's standing decisions.
- On an existing change branch behind main (`git rev-list --count HEAD..origin/main` not 0): `git merge --no-edit origin/main` before any work. Never rebase a pushed branch. If the merge cannot be resolved cleanly, `git merge --abort` and record friction.
- Start run metadata (timing, session id, SHAs) with a small script.

## 2. Claiming work: locks per change
Several workers may run at once, each on a different change.
- A status script lists changes as ready, stackable, parked or blocked. A run-lock script (`acquire <holder> <change-id>`) puts a lock comment on the change's single tracking issue. If busy, move to the next change. Release at the end.
- One tracking issue per change; its checklist is the task view. Observed 2026-11: per-task issues were retired because they only added noise.
- **Parked on an owner gate:** an owner question parks a change only when its next unticked task is a `Gate:` task. Put gated tasks last, so workers continue meanwhile.
- **Idle runs:** if the plan has a startable row, a worker should not end idle. The lead keeps at least three takeable changes (or a startable roadmap row). Dependent work starts early against a "Contract" task group (API schema, shared types, mocks) that the dependent lists as a need.
- Tasks are sized to at most about 30 minutes of work (observed 2026-11); a run may take several tasks, one branch and PR per change, each pushed once.

## 3. Implement, evaluate, escalate (`evaluate-escalate`)
Model tiers (the Agent tool `model`):
- **haiku:** isolated, well-defined work, search, running tests, repetitive edits.
- **sonnet:** the default, including most feature code and CI fixes.
- **opus:** only hard work: new crypto or protocol design, subtle security reasoning, cross-cutting design, merge reviews, and work a smaller tier already failed. Touching a sensitive path alone is not a reason.

Loop:
1. **Implement** with the exact task text, design excerpt, files and the verification command, plus the rules (reuse maintained OSS, real package versions, never print secrets).
2. **Verify yourself:** the task's verification command and `<quick-check>`. Never run `<full-ci>` locally; CI runs it.
3. **Independent evaluator:** a separate subagent, never the implementer, on sonnet (opus for tasks tagged hard). It gets the task, spec, diff, verification output and security rules, and answers PASS or FAIL: really done not stubbed, tests exercise real behaviour, no secret leak, no reinvented OSS, versions real.
4. **Tick a task only after verification and an evaluator PASS,** recorded by a script that the pre-push hook checks. Never enable auto-merge with an evaluator of `n/a`.
5. **Attempt 2 one tier up** (haiku to sonnet to opus), given the evaluator's reasons, failing output and attempt 1's diff.
6. **If attempt 2 fails:** commit as `WIP:` if it builds, else stash; write a progress entry; open a `needs-rescue` issue (see `help-routing.md`); move to an independent task or stop. Do not notify the owner.
- Same command failing twice with the same error: stop retrying and treat it as a task failure.
- A failing test run gets exactly one rerun, with both results recorded (flaky tests exist).
- Agents may only tick tasks, never rewrite task text. A guard script fails any agent branch that does.

## 4. Long commands (`long-commands`)
Anything that may take over about 2 minutes (cold build, image pull, `npm ci`, tool install) runs in the background with a hard timeout:
- `bg.sh start <name> <timeout-s> -- <cmd>` then `bg.sh wait <name>` (waits at most 110 s, prints the log tail and exit code; 124 means still running).
- Wait for state, not time. Foreground `sleep` is blocked in cloud runs.
- No prompts: `-y`, `CI=1`, `--no-pager`, `GIT_EDITOR=true`, `</dev/null`.
- Never run a subagent in the background and sleep for it; run it in the foreground. Never end a turn while only a background job runs.

## 5. Logging (`run-log`)
Before the final push of every run, including idle, parked, red-main and owner-blocked exits:
1. **progress.md entry** for the change (append-only): date, role, task and outcome, verification command and result, notes for the next session (traps, what to try).
2. **Metadata block** built by a script (never hand-assembled): orchestrator model, outcome, change, task, attempts, evaluator verdict, CI run, per-subagent role/tier/duration/tokens/tool uses, escalations, friction entries (`what`, `lost_s`, `fix_idea`). Use `unknown`, never guess. No secrets.
3. **agent-log comment** on a pinned `agent-log` issue: an agent marker line, 1 to 3 lines of summary, an Activity list (commits, comments, PRs, issues, each with a link, `none` when empty), then the block. Every comment an agent posts starts with the agent marker.

State lives in git and the agent-log issue, not in model memory.

## 6. Push checks and finishing
- Before every push to a branch with a PR, check the PR is still open. If it is merged or closed, do not push there: branch fresh from main, cherry-pick only commits not on main, rerun checks, open a new PR linking the old one. Check again before each later push in the session.
- Run `<quick-check>` and the tests you touched before every push. Push each branch once.
- Red default branch first. Then finish and unblock your own PRs (see `auto-merge-and-review.md`).
- **Never leave a VM with unpushed work.** Commit WIP and push before ending, even for a failed run, because the VM is thrown away.
- Instruction-size caps: cap common instructions, each role file and each skill by word count in CI, so instructions stay short (observed values: 660, 400 and 500 words). Active lessons cap: 5.

## Sources of truth
Your start script, run-lock script, background-runner script, run-metadata script and the skills.
