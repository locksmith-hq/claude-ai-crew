---
name: run-log
description: End-of-run logging for scheduled agents - the run-metadata block, friction entries, the change's progress entry, and the agent-log issue comment. Use before the final push of every run, including idle, parked, red-main and owner-blocked exits.
---

# Run log

## 1. progress entry
Append one entry to the change's `progress.md` in `<plan-repo>` (append-only), even if the run failed. Use this format:
```
## <UTC date time> <worker|lead|review>
- Task: <id> - <done|failed|blocked|ci-fix>
- Verified: <command> -> <result>
- Notes for next session: <traps, what to try next>
```

## 2. Metadata block
Build the block after your last commit and before the push (fix any `WARN` first), passing only your own fields on stdin:
```
bash "$CREW_HARNESS_DIR/scripts/run-meta.sh" block <<'EOB'
  orchestrator: <model>
  outcome: done|failed|rescue|blocked|idle|ci-fix|merged|rescued|learned|reviewed|healthy|answered
  change: <id|none>
  task: <ids|none>
  attempts: <n>
  evaluator: PASS|FAIL|n/a
  ci_run: <url|none>
  subagents:
    - {role: implementer|evaluator|reviewer|research, tier: <t>, duration_ms: <n|unknown>, tokens: <n|unknown>, tool_uses: <n|unknown>, result: ok|fail}
  escalations: <none|sonnet->opus>
  friction:
    - {what: "<anything that cost more than about 2 min>", lost_s: <n>, fix_idea: "<one line>"}
EOB
```
It prints one complete fenced block: don't wrap it. Take subagent numbers from each Agent result's usage; never guess (`unknown`). Never put secrets in it.

## 3. agent-log comment
Post one comment on the open issue labelled `agent-log` in `<plan-repo>`: first the line `<!-- agent -->`, then 1-3 lines of summary, then the activity list below, then the block.

Every run posts one, idle runs included. The activity list records everything this run changed, one line each with a link, and `none` for an empty heading:
```
**Activity**
- Commits: <short sha> <subject> (branch), from `git log <base_sha>..HEAD` on each branch you pushed
- Comments: <PR/issue link>: <one-line gist>
- PRs: <link> opened|pushed|labelled <label>|merged|closed: <why>
- Issues: <link> opened|edited|retitled|labelled|closed: <what>
```
Track these as you go. If all agents post as the owner account, GitHub cannot tell your actions from another run's. Every comment you post anywhere starts with `<!-- agent -->`. Use `gh api repos/$PLAN_REPO/issues/<n>/comments -f body=...`, because `gh issue` may be blocked in cloud runs.
