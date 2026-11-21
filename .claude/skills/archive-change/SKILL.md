---
name: archive-change
description: Archive a finished change inside the PR that ticks its last task, so its delta specs fold into the main specs and the roadmap shows it done. A separate archive PR is only for a change merged without one. Reference plan format is OpenSpec; another format plugs in by replacing step 2.
---

# Archive a change

Normally the PR that ticks the change's last task archives it (`prompts/worker.md`, last step): skip step 1 and run steps 2-4 on that PR's branch. Use a separate PR only for a finished change that was merged without its archive. All plan edits are made in `<plan-repo>` (`$CREW_PLAN_DIR`) with `crew_plan_git`.

1. Run `crew_plan_git checkout -b claude/archive-<id> origin/main`.
2. Archive the change: `openspec archive <id> --yes` run inside `$CREW_PLAN_DIR` (OpenSpec is the reference plan format; the result is `${PATH_CHANGES}/archive/<date>-<id>/`). If the CLI is missing, install it first with `npm i -g @fission-ai/openspec`. For a different plan format, move the change directory to `archive/<date>-<id>/` and fold its spec deltas by hand.
3. In `$PATH_ROADMAP`, set the change's status to done.
4. Run the plan repo's validation (`openspec validate --all` for the reference format) and `<quick-check>`.
5. Commit, push once, and open a PR in `$PLAN_REPO` with `-F draft=false`. Run `gh pr merge <n> --auto --merge`; it merges once the required checks pass.
