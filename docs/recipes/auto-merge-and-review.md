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
2. Protected paths need the owner's approval of this head commit (or of an earlier head with the same PR diff). An owner review, or an owner `approved` comment (below), re-runs the job. Security paths also need the `adversarial` workflow to pass on the head and get the strongest reviewer tier (below).
3. Completeness: every task file the PR touches is fully ticked (planning-only PRs exempt).
4. Review: an independent model (in a fresh session that did not write the code) reads the diff against the spec and the security rules and posts one verdict comment `merge-review <sha>: PASS|FAIL`. A PASS resolves the reviewer's open threads.
5. Reviewer by risk: the model comes from the plan repo's `crew.json` `review.tiers` (below). A diff that only touches `review.skip_globs` passes on CI and steps 1 to 3 alone.

Design details that mattered:
- **The status is set only by this workflow.** A PR whose job never ran has no status and cannot merge. A skipped job would count as passing; a missing status does not.
- **Patch-id reuse:** a PASS for an earlier head, or the owner's approval of one, still counts while the PR's own diff (patch-id against the default branch) is unchanged, for example after merging main in. This avoids re-reviewing for a no-op push.
- **Only the review action's verdict counts:** the verdict comment must come from a bot whose login starts with `claude`. Role Apps are bots too, so a role cannot post its own PASS.
- **Reviewer rules:** never push, never approve, inline comments only for real problems, a finding in the top-priority checks (secrets, spec) is a FAIL.
- **Keep the review in Actions, not a routine,** so the verdict comes from a fixed identity agents cannot act as (see `github-apps-and-identity.md`).
- A review that times out leaves the status pending. Recovery: disable and re-enable auto-merge.
- On-demand help: an `@claude` mention in a PR or issue comment, limited to people with write access.

## Reviewer tiers
Observed 2026-11: an Opus review on every PR (about 270 a week) cost far more than the risk needed; most diffs touch no secrets. Configure tiers in the plan repo's `crew.json`:

```json
"review": {
  "tiers": [
    {"name": "opus", "model": "claude-opus-5-5", "description": "secrets and the trust root",
     "paths": ["src/auth/", ".github/", "AGENTS.md"]},
    {"name": "sonnet", "model": "claude-sonnet-5-5", "description": "other code", "paths": []}
  ],
  "default_tier": "sonnet",
  "skip_globs": ["docs/", "changes/", "!*/tasks.md"]
}
```

- Tiers are listed strongest first; the first tier whose `paths` match any changed file wins. Otherwise, if every changed file matches `skip_globs`, no model reviews it. Otherwise `default_tier`.
- Globs match the whole path; `*` also crosses `/`; a trailing `/` is a whole directory; `!glob` in `skip_globs` keeps a path reviewed (last match wins). Keep task files reviewed: their ticks claim verified work.
- No `review.tiers`: every PR is reviewed with the workflow's `model` input. A bad config falls back to that model, never to a skip. An empty diff is reviewed.
- The tier script (`scripts/review-tier.sh`, at the pinned harness ref) and the config (the plan repo's default branch) never come from the PR, so a PR cannot lower its own review.
- Each review run adds a `review usage` annotation (model, turns, tokens, cost), so spend per PR can be read from the API.

## Adopting it in a code repo
Add one caller file, `.github/workflows/crew-review.yml`, copied from `templates/callers/crew-review.yml` (`crew init` writes it) with the three placeholders filled in. It holds triggers, permissions and inputs only; every check lives in the harness's reusable `review.yml` and in `crew.json`. Then make `merge-ready` a required status check on the default branch.

Secrets and variables (names only):
- `CLAUDE_CODE_OAUTH_TOKEN` (secret): the reviewer's subscription token. `ANTHROPIC_API_KEY` works instead.
- To read a private plan repo: the `CREW_APP_ID` variable and `CREW_APP_KEY` secret of the crew's GitHub App, or a `CREW_REPO_TOKEN` secret with read access to it. A public plan repo needs neither.
- The allowed bots are read from `crew.json` at run time (each role's `app` and `logins`), and the owner from `owner.login`; nothing is listed in the caller.
- Keep the caller's `name: crew-review` equal to the `review_workflow` the wake caller passes, so failed reviews wake the PR's author.

When switching from a repo-local review workflow, add the caller and delete the old workflow in the same PR, so two workflows never set `merge-ready` at once.

## Owner approval: three path lists
Observed 2026-11: a gate that covers whole files and folders gets bypassed with `--admin`, and the owner cannot review their own PRs. Keep the owner gate to what only the owner can decide (features and behaviour, look, budget), and give security-critical code a stronger automatic gate instead:

| List | Where | What it holds | Gate |
|---|---|---|---|
| Protected paths | `.github/CODEOWNERS` | spend and pricing: infrastructure, deploy workflows, licensing and entitlements, and the CODEOWNERS file itself | owner approval of the head commit (or of an earlier head with the same PR diff) |
| Owner keys | plan repo gate script | budget and identity keys in `crew.json` (for example dispatch, merge, owner, and each role's app and trigger keys) | owner approval of the head |
| Security paths | `crew.json` `merge.security_paths` | secret-handling code, workflows, agent instructions and skills | strongest reviewer tier (`review.tiers[0]`, else the `model` input) plus a passing `adversarial` workflow on the head; an owner `hold` label still stops the merge |

Keep `.github/CODEOWNERS` itself on the protected list, owned by the owner, so an agent cannot remove the gate. Security paths come from the plan repo's default branch, never from the PR, so a PR cannot shrink its own list. The workflow input `security_check` names the workflow that must pass (default `adversarial`); the job waits up to about 8 minutes for it. Agents never re-arm auto-merge on a "needs owner approval" failure; they open a decision issue instead.

**Approval by comment.** The head counts as owner-approved by an owner review, or by an issue comment on the PR from the owner login whose first line is exactly `approved`, with no `<!-- agent -->` marker, created after the head commit's committer date. A comment re-runs the job, so owner-authored PRs merge without `--admin`. A later push needs a new `approved`. Agent sessions that post as the owner must always carry the agent marker, and a marked comment never counts.

Agent-system changes should land in one weekly release PR (built by an optimizer) or a hotfix branch, so rules stay stable for a week. Observed 2026-11.

## Cost
Observed 2026-11: each review costs one Linux runner for up to about 10 minutes, and uses the subscription via an OAuth token stored as a repo secret, not API credits. A public repo has free standard runners.

## Finishing and unblocking PRs (agent procedure)
- Finish: archive the change in the PR if it completes one; comment a summary (what, how verified, risks); enable auto-merge. Never while a rescue issue is open for the change.
- Unblock own PRs oldest first, at most a few per run, locking the unit of work first: review FAIL (fix, resolve threads, push once), unticked tasks (finish or disable auto-merge), conflicts (merge main into the branch, never rebase a pushed branch; take main's lockfile and regenerate; keep both sides for lists), red CI (read annotations), stuck pending status.

## Sources of truth
The merge policy file, the review workflow header comment and the ruleset.
