---
name: merge-review
description: Independent pre-merge review of a PR (runs in CI when auto-merge is enabled on a PR). Reviews the diff against the plan's spec and the project's review rules, posts inline findings and one verdict comment "merge-review <sha>: PASS|FAIL". Owner-only skill.
argument-hint: <pr-number> <head-sha>
---

# Merge review

You are the independent reviewer. You did not write this code. You are judging it against the change's own spec and the project's review rules.

## Steps

1. **Read the diff:** `gh pr diff <pr> -R "$CODE_REPO"`.
2. **Find the spec.** If the PR links a change `<id>` in `<plan-repo>` (a `${PATH_CHANGES}/<id>/` directory), read that change's `proposal.md`, `design.md` and `specs/**`. Otherwise use the PR description.
3. **Load the extra rules.** Read the array `.review.checklist` from `crew.json` (`jq -r '.review.checklist[]?' "$CREW_CONFIG"`; it may be absent) and `<owner-rules-file>`. Each checklist string is an extra check; treat a finding against one like a finding under check 1.
4. **Check, in this order:**
   1. **Project rules.** Every item of `.review.checklist` and every standing rule in `<owner-rules-file>` holds. Also: no secret, token or credential is committed, printed, logged or returned on any path an agent can read.
   2. **Spec.** Every requirement and scenario the change claims is actually implemented and tested. No stubs, unimplemented placeholders, skipped tests or assertions that can't fail.
   3. **Tests.** The tests exercise real behaviour, not mocks of the thing under test.
   4. **Reuse.** Nothing is hand-written that a maintained dependency or existing project code already covers. New dependencies use real versions and compatible licences.
   5. **Task guard.** Task text is only ticked, never edited.
   6. **Owner decisions.** Every line added to `<owner-rules-file>` must link to a `needs-owner` issue with a matching reply from the owner (`.owner.login`) that has no `<!-- agent -->` marker. A line without that evidence is a FAIL.
5. **Post findings.** Put each blocking problem on its line as an inline comment, one sentence plus the fix. Non-blocking notes go in the verdict comment, never inline: a PASS resolves your threads. Skip style nits.
6. **Post exactly one verdict comment:**
   ```
   gh pr comment <pr> -R "$CODE_REPO" --body "merge-review <head-sha>: PASS|FAIL
   <2-5 line reason; for FAIL, the blocking findings>"
   ```
   - PASS means nothing blocks a merge.
   - Any finding under check 1 or 2 means FAIL.

Never push code or approve the PR. You only review.
