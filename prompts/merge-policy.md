<!-- Role: merge policy (owner-only; all roles follow it). Merging happens through GitHub auto-merge. -->
<!-- Domain-pack keys read: merge.required_checks, merge.protected_paths, repos.code, owner.login. -->
# Merge policy (owner-only file)

PRs merge themselves through GitHub auto-merge. There is no merge workflow, gate script or label.
(Example setting: a public repo, so CI minutes are free. Adjust if CI minutes cost money.)

- **Who enables it.** A PR belongs to the App that opened it. When it is finished, its author runs `gh pr merge <n> --auto --merge`. The lead may also do this, or fix, on a worker's PR. A worker never pushes to, labels or enables auto-merge on a PR it did not open, and never touches a PR the lead opened. Agents never call the merge API, approve, or use `--admin`.
- **What must pass** (a ruleset on main; GitHub merges the moment all pass):
  - required checks (`merge.required_checks` in the domain pack: hygiene, language builds and tests, platform checks, adversarial tests);
  - `merge-ready`, a commit status set only by the review workflow once auto-merge is on: the change is complete (planning-only PRs exempt) and the independent Claude (Opus) review posted `merge-review <sha>: PASS`. A PASS still holds while the PR's own diff (patch-id) is unchanged, e.g. after merging main in. Owner PRs pass it without review;
  - every review thread resolved, no conflicts;
  - for paths in main's `.github/CODEOWNERS` (the agent system and trust root, so the weekly harness release and hotfixes wait for the owner, plus any secret- or security-critical code), the owner's approval of the head commit; `merge-ready` checks it and re-runs on the owner's review.
- **Stop a merge:** `gh pr merge <n> --disable-auto`.
- Merges always use a merge commit, so `git revert -m 1 <sha>` undoes any of them.
- If main CI goes red after a merge, fixing it comes before any other work.
- Admins bypass the ruleset; only the owner is an admin.
- This file, `.github/CODEOWNERS`, the `merge-review` skill and the workflows change only in owner sessions, or through a lead PR that the owner approves.
