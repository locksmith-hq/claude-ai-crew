---
name: run-start
description: Start of every scheduled agent run. Runs preflight (container runtime, toolchain, registries, package manager, disk, network), starts run metadata, prints active lessons, and brings the change branch up to date. Use first, before any other work.
---

# Run start

The harness checkout is your own scripts directory. `agent-start.sh` exports `CREW_HARNESS_DIR` (the harness path). Every other skill calls scripts as `bash "$CREW_HARNESS_DIR/scripts/<name>.sh"`. If it is unset in a later shell, export it again from the harness checkout path.

1. Run `bash "$CREW_HARNESS_DIR/scripts/agent-start.sh" <kind> [persona]`, where `<kind>` is one of worker, lead, review, health or research, and `persona` is the role key your routine prompt names (for example `worker-a`; roles that share one runtime must pass it). It switches to that role's GitHub App; if the environment holds App keys but none for your persona, it fails. Only an environment with no keys acts as the owner account.
   - It prints one line per check: `OK`, `FIXED`, `WARN` or `FAIL`.
   - Fix every `FAIL` before doing real work.
   - In cloud sessions `gh api user` and `GET /users/...` are answered by the session proxy (the owner) and say nothing about identity: to check, run `scripts/agent-identity.sh whoami`, and after your first post run `scripts/agent-identity.sh verify-author <its url>`; stop only when it reports a mismatch.
   - Record each `WARN` or `FAIL` line, and each `FIXED` except the container runtime (expected), as `friction` (format: `run-log` skill).
2. Read the active lessons the script prints at the end (`<lessons-file>`), and follow them. Also read `<owner-rules-file>`: those are the owner's standing decisions.
3. If you work on an existing `claude/change-<id>` branch and `git rev-list --count HEAD..origin/main` is not 0, run `git merge --no-edit origin/main` before any work. Never rebase a pushed branch. If the merge conflicts in a way you can't resolve cleanly, run `git merge --abort` and record it as friction.

## Gotchas (cloud VM, observed 2026-11, verified on one provider only)
- A container registry may return 403 even though the docs allow it. Fall back to Docker Hub images.
- Docker Hub rate-limits anonymous pulls (429). Preflight starts the daemon with the `mirror.gcr.io` registry mirror; if it warns `docker-mirror`, record it as friction and don't loop on retries after a 429.
- `service docker start` can fail. Preflight falls back to `dockerd &`, so don't start the container runtime by hand.
- The VM may run as root. A test that relies on non-root behaviour may skip itself, which is expected.
- A web test suite needs installed dependencies. If preflight warns about it, start the install with the `long-commands` skill.
