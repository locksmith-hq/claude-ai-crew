# Domain pack

Everything the harness needs to know about your project lives in a **domain pack**: a `crew.json` file in
your plan repo, plus the rules and plan files it points at. The harness never hardcodes a project.

## `crew.json`

```json
{
  "project": "example",
  "owner": {
    "login": "your-github-login"
  },
  "repos": {
    "harness": "your-org/claude-ai-crew",
    "plan": "your-org/example-plan",
    "code": [
      "your-org/example"
    ]
  },
  "commands": {
    "quick": "make quick",
    "ci": "make ci",
    "setup": "make setup",
    "free_disk": "rm -rf build/cache",
    "free_disk_skip_if_running": "make"
  },
  "paths": {
    "decisions": "decisions.md",
    "owner_rules": "owner.md",
    "lessons": "lessons.md",
    "roadmap": "roadmap.md",
    "changes": "changes/",
    "schedules": "schedules.md",
    "research": "research/"
  },
  "issues": {
    "agent_log": 0,
    "harness_backlog": 0
  },
  "schedule": {
    "timezone": "UTC",
    "weekly_reset_day": "Saturday",
    "harness_start_date": "2026-01-01"
  },
  "merge": {
    "required_checks": [
      "ci"
    ],
    "protected_paths": [
      ".github/workflows/",
      "crew.json",
      "owner.md"
    ]
  },
  "research": {
    "dependency_watchlist": []
  },
  "review": {
    "checklist": [
      "No secret or credential is added to the repo or logged"
    ]
  },
  "preflight": [
    {
      "name": "node",
      "cmd": "node --version",
      "level": "fail",
      "hint": "node is missing"
    },
    {
      "name": "deps",
      "cmd": "test -d node_modules",
      "level": "warn",
      "hint": "install dependencies in the background before tests"
    }
  ],
  "stack_checks": [],
  "roles": {
    "lead": {
      "app": "example-lead",
      "trigger": "trig_REPLACE_ME",
      "secret": "LEAD_FIRE_TOKEN"
    },
    "worker-a": {
      "app": "example-worker-a",
      "trigger": "trig_REPLACE_ME",
      "secret": "WORKER_A_FIRE_TOKEN"
    },
    "pm": {
      "app": "example-pm",
      "trigger": "trig_REPLACE_ME",
      "secret": "PM_FIRE_TOKEN"
    },
    "research": {
      "app": "example-research",
      "trigger": "trig_REPLACE_ME",
      "secret": "RESEARCH_FIRE_TOKEN"
    }
  },
  "channels": {
    "needs-rescue": {
      "from": [
        "worker-a"
      ],
      "to": "lead",
      "on_close": "raiser"
    },
    "needs-owner": {
      "from": [
        "lead"
      ],
      "to": "owner",
      "on_reply": "raiser",
      "on_close": "worker-a"
    },
    "debate": {
      "between": [
        "pm",
        "lead"
      ],
      "turns": 3,
      "escalate_to": "lead"
    },
    "needs-research": {
      "from": [
        "lead",
        "pm",
        "worker-a"
      ],
      "to": "research",
      "on_close": "raiser"
    },
    "needs-work": {
      "from": [
        "worker-a"
      ],
      "to": "pm",
      "on_close": "raiser"
    }
  },
  "default_worker": "worker-a",
  "trust_root": [
    ".github/workflows/",
    "crew.json",
    "owner.md"
  ],
  "agent_system": [
    "prompts/",
    "skills/",
    "scripts/"
  ]
}
```

| Key | Meaning |
|---|---|
| `project` | Short name used in prompts and logs |
| `owner.login` | The human owner. Only this login's unmarked comments instruct agents |
| `repos.harness` / `repos.plan` / `repos.code` | The repos the routines attach. `code` is a list |
| `commands.quick` | The cheap local check run before every push |
| `commands.ci` | The full CI command. Agents never run it locally; CI does |
| `commands.setup` | One-time environment setup for a fresh VM |
| `paths.*` | Files in the plan repo: decisions log, the owner's standing rules, lessons, roadmap, planned changes |
| `roles.*` | One entry per role: its GitHub App slug, its routine trigger id, and the **name** of the secret holding its API trigger token (never the token) |
| `paths.schedules` / `paths.research` | The schedules table (routines, cadence, models) and the folder of research notes |
| `issues.agent_log` / `issues.harness_backlog` | Issue numbers: where run summaries are posted and where harness ideas are collected |
| `schedule.timezone` / `schedule.weekly_reset_day` / `schedule.harness_start_date` | Used by the health check, the weekly harness release and run-window math |
| `merge.required_checks` | Names of the CI checks that must pass before auto-merge |
| `merge.protected_paths` | Paths that need the owner's approval of the head commit (the trust root and security-critical code) |
| `research.dependency_watchlist` | Optional list of dependencies or tools the research role watches |
| `commands.free_disk` / `commands.free_disk_skip_if_running` | Command that frees build caches when disk runs low (`BG_MIN_FREE_GB`, default 8), and a process name that blocks it while running |
| `stack_checks` | Optional list of `{name, cmd}` checks of your local stack; `harness-check.sh` prints PASS/FAIL for each |
| `review.checklist` | Optional list of extra rules the independent reviewer must check on every PR (project-specific security or style rules) |
| `preflight` | Optional list of tool checks run at the start of every run: `{name, cmd, fix, level, hint, wait}`. A failing `cmd` runs `fix` in the code checkout and polls `cmd` for `wait` seconds (default 20). `level` is `warn` or `fail` (default `fail`). `$SUDO` is empty as root, otherwise `sudo -n` |
| `mentions` | Optional map of wake handles to roles; defaults to `@<project>-<role>` |
| `schedules` | Optional: `avoid_hours_utc` (weekday UTC hours no worker runs, default 15 to 20) and `roles.<role>` overrides (`cron` list, `enabled: false`). Schedules are generated from the roles and these settings by `crew schedules` |
| `roles.<role>.app_id` | Optional: the role's GitHub App id (public). Set it: the lookup fallback fails in cloud sessions |
| `roles.<role>.key_env` / `id_env` | Optional: the names of the environment variables holding that role's App key and App id, when your environment already uses other names than `AGENT_APP_KEY_<ROLE>` / `AGENT_APP_ID_<ROLE>`. The App id is taken from `roles.<role>.app_id` (public, preferred), else the id variable, else looked up from the public `GET /apps/<slug>` (unreliable in cloud sessions: shared-IP rate limits and proxies) |
| `channels` | Who may open which help channel and who is woken (same shape the routing script reads) |
| `default_worker` | The worker woken when nothing names one (for example red main CI) |
| `trust_root` | Paths that agents may never change on their own branches |
| `agent_system` | Paths that change only in the periodic harness-release PR or a hotfix |

Placeholders in the prompts map to these keys: `<project>` is `project`, `<owner>` is `owner.login`,
`<code-repo>` is `repos.code[0]`, `<plan-repo>` is `repos.plan`, `<quick-check>` is `commands.quick`,
`<full-ci>` is `commands.ci`, `<decisions-file>`, `<owner-rules-file>` and `<lessons-file>` are `paths.*`.

## What else belongs in your plan repo
- **Owner rules** (`paths.owner_rules`): the standing decisions that every agent reads at run start.
- **Decisions log** (`paths.decisions`): numbered decisions the lead records, listed in the daily summary
  as "decided, reply to reverse".
- **Lessons** (`paths.lessons`): short numbered lessons agents print at run start. Project-independent
  ones are worth contributing to [docs/recipes/lessons.md](recipes/lessons.md).
- **Roadmap and planned changes**: what workers claim.

See [examples/domain-pack](../examples/domain-pack) for a starter.
