# Auto-merge and independent review

PRs merge themselves through GitHub auto-merge once required checks, an independent AI review status and (for protected paths) the owner's approval all pass.

## Policy design
- **Author enables auto-merge.** A PR belongs to the App that opened it. When finished, its author runs `gh pr merge <n> --auto --merge`. The lead role may also fix or enable auto-merge on a worker's PR. A worker never touches another worker's PR or the lead's. Agents never approve, call the merge API or use `--admin`.
- **GitHub does the merging.** No merge script, queue or label (observed 2026-11: a custom merge gate and label were replaced by plain auto-merge and deleted, which removed a class of bugs).
- **Required checks** (a ruleset on the default branch): the same CI jobs a human PR needs, plus the review status below, no unresolved review threads, no conflicts.
- **Merge commits only,** so `git revert -m 1 <sha>` undoes any merge.
- **Red default branch first:** if CI on the default branch is red after a merge, fixing it comes before any other work.
- **Stop a merge:** `gh pr merge <n> --disable-auto`.
- Only the owner is admin and can bypass the ruleset.

## The `merge-ready` review status
A workflow runs when auto-merge is enabled on a PR and on every push to such a PR. It sets a commit status (for example `merge-ready`) that is a required check. Checks, in order:
1. Owner PRs on a non-agent branch pass (the owner reviews their own work).
2. Protected paths need the owner's approval of this head commit. An owner review re-runs the job.
3. Completeness: every task file the PR touches is fully ticked (planning-only PRs exempt).
4. Review: an independent model (the strongest tier, in a fresh session that did not write the code) reads the diff against the spec and the security rules and posts one verdict comment `merge-review <sha>: PASS|FAIL`.

Design details that mattered:
- **The status is set only by this workflow.** A PR whose job never ran has no status and cannot merge. A skipped job would count as passing; a missing status does not.
- **Patch-id reuse:** a PASS for an earlier head still counts while the PR's own diff (patch-id against the default branch) is unchanged, for example after merging main in. This avoids re-reviewing for a no-op push.
- **Reviewer rules:** never push, never approve, inline comments only for real problems, a finding in the top-priority checks (secrets, spec) is a FAIL.
- **Keep the review in Actions, not a routine,** so the verdict comes from a fixed identity agents cannot act as (see `github-apps-and-identity.md`).
- A review that times out leaves the status pending. Recovery: disable and re-enable auto-merge.
- On-demand help: an `@claude` mention in a PR or issue comment, limited to people with write access.

## Owner approval for protected paths
List protected paths in `.github/CODEOWNERS`: the agent system itself (instructions, skills, scripts, workflows), the merge policy and the trust root. A PR touching them waits for the owner's approval of the head commit. Agents never re-arm auto-merge on a "needs owner approval" failure; they open a decision issue instead.

Agent-system changes should land in one weekly release PR (built by an optimizer) or a hotfix branch, so rules stay stable for a week. Observed 2026-11.

## Cost
Observed 2026-11: each review costs one Linux runner for up to about 10 minutes, and uses the subscription via an OAuth token stored as a repo secret, not API credits. A public repo has free standard runners.

## Finishing and unblocking PRs (agent procedure)
- Finish: archive the change in the PR if it completes one; comment a summary (what, how verified, risks); enable auto-merge. Never while a rescue issue is open for the change.
- Unblock own PRs oldest first, at most a few per run, locking the unit of work first: review FAIL (fix, resolve threads, push once), unticked tasks (finish or disable auto-merge), conflicts (merge main into the branch, never rebase a pushed branch; take main's lockfile and regenerate; keep both sides for lists), red CI (read annotations), stuck pending status.

## Sources of truth
The merge policy file, the review workflow header comment and the ruleset.
