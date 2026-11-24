#!/usr/bin/env bash
# Guard, run in CI of the repo that holds the plan and the harness files (default: the plan repo; set GUARD_DIR
# to check another checkout). Two jobs:
#  1. Task guard. On implementation branches (claude/change-*, change/*) an agent may only tick or untick
#     plan tasks (reference format: <changes>/<id>/tasks.md), never edit, add or remove task text.
#     progress.md is append-only. Planning branches may edit freely.
#     Why: models rewrite Markdown task lists to look done
#     (https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents).
#  2. Agent-system guard. Paths come from the domain pack (crew.json), not from this script:
#       (read from the base crew.json when origin/main has one)
#       .agent_system  path prefixes that change only on a *harness-release-* branch (one PR a week, built by the
#                      optimizer, approved by the owner) or a *hotfix-* branch (red main, a security fix, every
#                      run failing). This binds every branch, owner sessions included; other findings go to the
#                      harness-backlog issue.
#       .trust_root    path prefixes agents (claude/* branches) never change: gates, guards, routing, workflows,
#                      hard rules. Counts as agent system too.
#     The owner-rules file and the decisions file ($PATH_OWNER_RULES, $PATH_DECISIONS) are append-only for agents
#     and may be appended on any branch; they are exempt from the two lists above.
#     Branch naming (claude/*, harness-release, hotfix) is the generic convention of this harness.
# Usage: BRANCH=<name> scripts/check-task-edits.sh   (BRANCH defaults to the current git branch)
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/crew-env.sh
. "$here/lib/crew-env.sh"
cd "${GUARD_DIR:-$CREW_PLAN_DIR}" || exit 2
CH=${PATH_CHANGES%/}

branch="${BRANCH:-$(git rev-parse --abbrev-ref HEAD)}"

# The lists are read from the BASE version of crew.json when origin/main has one, so a branch cannot widen its own
# permissions by editing the config in the same PR; otherwise from the working copy.
cfg=$(git show origin/main:crew.json 2>/dev/null || cat "$CREW_CONFIG")
trust=(); while IFS= read -r p; do [ -n "$p" ] && trust+=("$p"); done < <(jq -r '.trust_root[]?' <<<"$cfg")
harness=("${trust[@]+"${trust[@]}"}"); while IFS= read -r p; do [ -n "$p" ] && harness+=("$p"); done < <(jq -r '.agent_system[]?' <<<"$cfg")
# shortcut: an empty pathspec list would match every file, so each list is skipped when empty.
append_only=("$PATH_OWNER_RULES" "$PATH_DECISIONS")
exempt() { grep -vxF -e "$PATH_OWNER_RULES" -e "$PATH_DECISIONS" || true; }

protected_fail=0
# Append-only files: no line of the base version is removed or changed. New lines may sit anywhere, so a
# `merge=union` merge (.gitattributes) of two branches that both appended still passes.
kept() { ! grep -q '^<' <(diff <(git show "$1") "$2"); }   # <rev:path> <file>
if git rev-parse -q --verify origin/main >/dev/null; then
  ob=$(git merge-base HEAD origin/main)
  if [ ${#harness[@]} -gt 0 ]; then
    changed=$(git diff --name-only "$ob" -- "${harness[@]}" | exempt)
    case "$branch" in *harness-release-*|*hotfix-*) ;; *)
      if [ -n "$changed" ]; then
        echo "task-edit guard: '$branch' changes agent-system files outside the weekly release:"; echo "$changed"
        echo "  Add the finding to the harness-backlog issue, or use a *hotfix-* branch for red main, a security fix or every run failing."
        protected_fail=1
      fi ;;
    esac
  fi
  if [[ "$branch" == claude/* ]]; then
    # Append-only files: agents may add new lines, never edit existing ones.
    for f in "${append_only[@]}"; do
      if git cat-file -e "$ob:$f" 2>/dev/null; then
        { [ -f "$f" ] && kept "$ob:$f" "$f"; } || { echo "task-edit guard: $f is append-only for agents"; protected_fail=1; }
      fi
    done
    if [ ${#trust[@]} -gt 0 ]; then
      tchanged=$(git diff --name-only "$ob" -- "${trust[@]}" | exempt)
      if [ -n "$tchanged" ]; then
        echo "task-edit guard: agent branch '$branch' changed trust-root files (owner-only):"; echo "$tchanged"
        protected_fail=1
      fi
    fi
  fi
fi

case "$branch" in
  claude/change-*|change/*) ;;
  *) echo "task-edit guard: task checks skipped on branch '$branch'"; exit "$protected_fail" ;;
esac

base_ref=origin/main
if ! git rev-parse -q --verify "$base_ref" >/dev/null; then
  echo "task-edit guard: $base_ref not found (fetch it); skipping" >&2; exit 0
fi
base=$(git merge-base HEAD "$base_ref")

# Strip the checkbox state so only a tick/untick compares equal.
norm() { sed -E 's/^([[:space:]]*- )\[[ xX]\]/\1[?]/'; }

# Where a change file lives now: in place, or moved by archiving into archive/<date>-<id>/.
current() { [ -f "$1" ] && { echo "$1"; return; }
  find "$CH/archive" -path "*-$(basename "$(dirname "$1")")/$(basename "$1")" 2>/dev/null | sort | tail -1; }

fail=$protected_fail
while IFS= read -r f; do
  git cat-file -e "$base:$f" 2>/dev/null || continue   # a new tasks.md (new change or archive copy) is allowed
  cur=$(current "$f")
  if [ -z "$cur" ]; then echo "task-edit guard: $f was deleted"; fail=1; continue; fi
  if ! diff -q <(git show "$base:$f" | norm) <(norm < "$cur") >/dev/null; then
    echo "task-edit guard: $cur changed beyond ticking checkboxes:"
    diff <(git show "$base:$f" | norm) <(norm < "$cur") | head -20 || true
    fail=1
  fi
done < <(git diff --name-only "$base" -- "$CH/*/tasks.md")

# progress.md is append-only: every earlier line stays, unchanged and in order.
while IFS= read -r f; do
  git cat-file -e "$base:$f" 2>/dev/null || continue
  cur=$(current "$f")
  if [ -z "$cur" ] || ! kept "$base:$f" "$cur"; then
    echo "task-edit guard: $f is append-only, but earlier entries changed"; fail=1
  fi
done < <(git diff --name-only "$base" -- "$CH/*/progress.md")

[ "$fail" -eq 0 ] && echo "task-edit guard: OK ($branch)"
exit "$fail"
