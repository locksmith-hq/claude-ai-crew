# Merging plan-repo PRs without auto-merge

A private plan repo on GitHub's free plan has no branch protection, rulesets or native auto-merge (the API answers
403 and `allow_auto_merge` is `false`). Agent PRs there (ticks, progress entries, plans, decisions) then stay open,
and since every role reads the plan from the default branch, ticks stay invisible and the ready-queue goes wrong.
Observed 2026-11.

The fix is a small merge-bot workflow in the plan repo. It decides from the API on every event and merges with the
workflow token. Agents stop calling `gh pr merge --auto` on plan-repo PRs (`prompts/merge-policy.md`).

## Triggers
- `workflow_run` of the secret-scan workflow (completed), so a PR merges as soon as its scan passes.
- `pull_request_target` (opened, reopened, synchronize, ready_for_review, labeled, unlabeled).
- `workflow_dispatch` with an optional PR number (empty = every open PR) and a dry-run flag that prints the decision.
- A push to the default branch re-checks every open PR, since conflicts may have changed.

## Merge rules (all required)
1. PR open, not draft, base is the default branch.
2. Author is a role App from the default branch's `crew.json` (`roles.*.app` + `[bot]`, or `roles.*.logins`),
   never from the PR's own copy.
3. Head branch is an agent branch (`claude/*`).
4. The secret-scan check passed on the head commit, and every `merge.required_checks` name present on that commit
   passed. Ignore other checks: the bot's own run can show as a pending check and would block itself.
5. No `hold`, `needs-owner` or `do-not-merge` label.
6. No changed file (renames: old and new path) under `merge.protected_paths`, unless the owner's latest review of the
   current head commit is APPROVED. Add the decision script itself to `merge.protected_paths`.
7. Task-edit guard, the `scripts/check-task-edits.sh` rules on text fetched through the contents API (base at the
   merge base): on `claude/change-*` branches tasks may only be ticked and progress only appended (an archive move
   compares against the archived copy); on any `claude/*` branch the owner-rules and decisions files are
   append-only. Do not run the script itself: its trust-root rule would refuse owner-approved protected changes,
   and it needs a checkout of the PR.
8. No merge conflicts (`mergeable`; GitHub computes it lazily, so retry a few times).

Merge through `PUT /pulls/{n}/merge` with the checked head `sha`, so a push after the decision makes the merge
fail instead of merging unchecked commits. Otherwise write one line to the job summary; comment on the PR (once per
head sha, with `<!-- agent -->` and a bot marker) only for blockers the author can fix: conflict, guard, scan.

## Safety
- Never check out or run PR code. Read the PR through the API; check out only the default branch (sparse, the
  decision script and `crew.json`, `persist-credentials: false`).
- Refuse `workflow_dispatch` off the default branch: dispatch runs the workflow file from the chosen ref.
- Job-level permissions only: `contents: write`, `pull-requests: write`, `checks: read`, `statuses: read`.
- No `secrets: inherit`; pin actions by commit sha; PR titles, branches and bodies go through env, never into
  `${{ }}` inside `run:`.
- Keep the decision a pure script over JSON files (pull, files, reviews, check runs, file texts) with an offline
  fixture test: eligible, wrong author, protected path with and without owner approval, failed and pending scan,
  draft, hold label, task text edited, conflict.

## Limits
- It is not branch protection: anyone with write access, role Apps included, can still push to the default branch.
  The "never push to main" rule and the Apps' permissions remain the control. GitHub Team gives real protection.
- Merges and comments by the workflow token start no other workflow, so they wake no agent; agents see them on
  their next run.
- A review event does not run it (that event would run the PR's own workflow file): after approving a protected
  PR, the owner dispatches the workflow for it or merges by hand. The workflow token cannot merge a PR that changes
  workflow files; the owner merges those.
