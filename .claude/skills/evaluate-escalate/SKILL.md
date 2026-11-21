---
name: evaluate-escalate
description: The implement, independent evaluate, escalate-one-tier loop for doing one plan task (or fixing CI / main). Use for every task a worker or lead rescue does; includes how to open a needs-rescue issue when both attempts fail.
---

# Evaluate, then escalate

## Tiers (Agent tool `model`)
- `haiku`: isolated, well-defined work and repetitive edits.
- `sonnet`: the default, including most feature code (plumbing, routing, CLI, tests).
- `opus`: only hard, complex tasks: tagged `[opus]`, or a Sonnet attempt that failed evaluation (step 5). Touching a sensitive path alone is not a reason; the domain pack may list protected paths that need extra review, not a bigger model.

You may implement small tasks yourself (`self: true` in run-log); step 3 still applies.

Cloud subagents may always run async ("Async agent launched"): end the turn with one status line; the hand-back resumes you. No Monitor or sleep heartbeats. Never end a turn while only a `bg.sh` job runs: poll `bg.sh wait`.

## Loop
1. **Implement.** Give the implementer:
   - the exact task text, the design excerpt, the files and the verification command;
   - the rules: reuse maintained open-source packages before writing code, use real package versions from the registry, and never print secrets.
2. **Verify it yourself.** Run the task's verification command and `<quick-check>` (never `<full-ci>`; CI runs it). Use the `long-commands` skill if either is slow.
3. **Evaluate.** A separate subagent, never the implementer, runs on `sonnet`, or on `opus` for `[opus]` tasks. Give it the task, the spec excerpt, `git diff`, the verification output and the project's security rules (from `<owner-rules-file>` and the repo's agent instructions). It answers PASS or FAIL with reasons, checking:
   - the task is really done, not stubbed;
   - the tests exercise real behaviour;
   - no secret can leak;
   - no reinvented open-source package;
   - the package versions are real.
4. Tick only after verification and the evaluator pass, recorded with `bash "$CREW_HARNESS_DIR/scripts/run-meta.sh" eval PASS` (pre-push refuses ticks without it). Never enable auto-merge with `evaluator: n/a`.
5. Otherwise, make attempt 2 one tier up (haiku -> sonnet -> opus). Give the new implementer the evaluator's reasons, failing output and attempt-1 diff; repeat steps 2-4.
6. If attempt 2 also fails:
   - commit with a `WIP:` message if the code builds, otherwise `git stash`;
   - write a progress entry;
   - open a `needs-rescue` issue in `$PLAN_REPO` titled `Rescue: <change> <task>`, or comment on an existing one. Its first line is one plain sentence: what is stuck and why (the board shows it). Then include the branch, the tiers tried, the evaluator's reasons, up to 60 lines of failing output, and your diagnosis.

   Don't notify the owner; the lead routine rescues it. Move on to an independent task, or stop.
