# Domain pack

Everything the harness needs to know about your project lives in a **domain pack**: a `crew.json` file in
your plan repo, plus the rules and plan files it points at. The harness never hardcodes a project.

## `crew.json` holds overrides only

The harness ships `crew.defaults.json` (the generic crew: role keys `lead`, `pm`, `research`, `worker-a/b/c`
with their batched flags, the help channels, the debate cap, the dispatch defaults). Your plan repo's `crew.json`
is merged over it (`scripts/lib/crew-env.sh`): objects merge recursively, arrays and scalars in your file
replace the default. So a minimal `crew.json` is the owner, the repos and what is yours, for example
`roles.<role>.name`, `.app`, `.trigger`, `.secret`. The listing below is the full form (what the merged file
looks like); you only need to write the parts that differ from the defaults.

Handles: `@<project>-<role>` and `@<org>/<role>` wake a role; a role's optional `name` adds
`@<project>-<slug>` and `@<org>/<slug>` (lowercase, spaces to `-`: name "Atlas Lead" gives `@acme-atlas-lead`).
Keep names, logins, repo names and ids in your `crew.json`, never in the harness.

## Full `crew.json`

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
      ".github/workflows/review.yml",
      ".github/workflows/wake.yml",
      ".github/workflows/change-sync.yml",
      ".github/workflows/owner-alert.yml",
      ".github/workflows/role-run.yml",
      ".github/workflows/crew-*",
      ".github/workflows/aws-*",
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
    ".github/workflows/review.yml",
    ".github/workflows/wake.yml",
    ".github/workflows/change-sync.yml",
    ".github/workflows/owner-alert.yml",
    ".github/workflows/role-run.yml",
    ".github/workflows/crew-*",
    ".github/workflows/aws-*",
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
| `review.tiers` | Optional list of reviewer tiers, strongest first: `{name, model, paths, description}`. The first tier whose `paths` globs match any changed file picks the review model (`scripts/review-tier.sh`). Without it every review uses the review workflow's `model` input |
| `review.default_tier` | The tier name for PRs no tier's `paths` match (required with `review.tiers`; its `paths` may be empty) |
| `review.skip_globs` | Optional globs of paths that need no model review (docs, planning). When every changed file matches, `merge-ready` passes on CI and the other checks alone. `!glob` keeps a path reviewed, last match wins. Globs: `*` also crosses `/`, a trailing `/` is a whole directory |
| `preflight` | Optional list of tool checks run at the start of every run: `{name, cmd, fix, level, hint, wait}`. A failing `cmd` runs `fix` in the code checkout and polls `cmd` for `wait` seconds (default 20). `level` is `warn` or `fail` (default `fail`). `$SUDO` is empty as root, otherwise `sudo -n` |
| `mentions` | Optional map of extra wake handles to roles; the defaults are `@<project>-<role>`, `@<org>/<role>` and, for a role with a `name`, `@<project>-<slug>` and `@<org>/<slug>` |
| `roles.<role>.name` | Optional display name of the role; its slug is a wake handle (see above) |
| `schedules` | Optional: `avoid_hours_utc` (weekday UTC hours no worker runs, default 15 to 20) and `roles.<role>` overrides (`cron` list, `enabled: false`). Schedules are generated from the roles and these settings by `crew schedules` |
| `roles.<role>.app_id` | Optional: the role's GitHub App id (public). Set it: the lookup fallback fails in cloud sessions |
| `roles.<role>.bot_id` | Optional but needed in cloud sessions: the bot account's user id (public; `gh api users/<app>%5Bbot%5D -q .id`), used for the commit noreply email. Without it `agent-identity.sh` looks it up with `GET /users/<bot>`, which a cloud session proxy refuses (403), so run-start fails with "cannot look up the bot user id" |
| `roles.<role>.key_env` / `id_env` | Optional: the names of the environment variables holding that role's App key and App id, when your environment already uses other names than `AGENT_APP_KEY_<ROLE>` / `AGENT_APP_ID_<ROLE>`. The App id is taken from `roles.<role>.app_id` (public, preferred), else the id variable, else looked up from the public `GET /apps/<slug>` (unreliable in cloud sessions: shared-IP rate limits and proxies) |
| `roles.<role>.logins` | Optional: older GitHub logins of the role (for example `old-app[bot]` after an App rename), so earlier PRs and comments still map to it |
| `roles.<role>.batched` | Optional, `true` for expensive roles: only an owner tag wakes them at once; other wakes label the issue `wake-<role>` and the wake workflow's tick (a `workflow_dispatch` every 2 h) fires the role once for its queue |
| `dispatch` | Optional: workers fired by an external dispatcher instead of events. `workers` lists them (the wake workflow then fires them only for an owner tag); `slots`, `max_5h`, `max_day`, `run_minutes` are its budget, read by the dispatcher and the PM |
| `paths.roles` | Optional folder (default `roles/`) of project additions to a role prompt: `<role>.md` is read after the harness role file |
| `channels` | Who may open which help channel and who is woken (same shape the routing script reads). `to` is one role or a list of roles, each woken once (for example `"needs-work": {"to": ["pm", "lead"]}`) |
| `default_worker` | The worker woken when nothing names one (for example the owner's own PR); red main CI wakes the lead |
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
