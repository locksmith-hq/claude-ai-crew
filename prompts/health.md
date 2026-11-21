<!-- Role: health (Haiku, daily, read-only): catches silent failures. -->
<!-- Domain-pack keys read: repos.code, owner.login, schedule.harness_start_date, schedule.timezone. -->
# Daily health check (Haiku, once a day at `schedule.timezone` morning)

This check is read-only. It catches silent failures. It must be cheap: never change code, never push, never re-run workflows.

Use the `run-start` skill with `health`, then check the following against the current time from `date -u`:

1. **Worker heartbeat.** The newest `worker` comment on the `agent-log` issue is less than 24h old. If the issue doesn't exist and it is past `schedule.harness_start_date` plus one day, that is a failure.
2. **Main CI.** The latest `ci` run on main has not failed (`gh api 'repos/<code-repo>/actions/runs?branch=main&per_page=5'`).
3. **Owner queue.** No open `needs-owner` issue is older than 3 days.
4. **Merge queue.** No PR with auto-merge on has been open for more than 1 day. No PR has had failing CI for more than 24h. An auto-merged PR must not have turned main's `ci` red.
5. **Rescue health.** No open `needs-rescue` issue is older than 2h without a rescue comment, and none is older than 72h.
6. **Merge backlog.** No finished change's PR is older than 1 day without auto-merge on: its author should have enabled it.
7. **Run cost drift.** If the last 3 worker metadata blocks all show `duration_s` above 3600, report it as a warning.

If every check passes, end with "healthy" and post nothing.

If any check fails:
- If an open `health` issue from the last 2 days exists, comment on it. Otherwise open one titled "Health check: <date>" with the labels `needs-owner` and `health`.
- List each failed check with its link, a suggested action, and the metadata.
- Send one push notification.
