#!/usr/bin/env bash
# Collects the deterministic part of a scheduled agent run's metadata.
#   run-meta.sh start <kind>   record start time and HEADs (call first thing in a run)
#   run-meta.sh report         print the YAML body (no fences) for the run so far
#   run-meta.sh block < fields print the complete ```yaml block: report + agent fields from stdin
#   run-meta.sh eval PASS|FAIL record the independent evaluator's verdict for push-check
#   run-meta.sh push-check     pre-push hook: refuse a push that ticks tasks without an evaluator PASS
# The agent appends `subagents:` and outcome fields itself (it is the only one that knows them).
# Never prints secret values: only allow-listed env var names that look like session ids.
# Plan format: task ticks (`- [x]`) in `*tasks.md` files are the reference plan format (OpenSpec-style
# changes). A different plan format plugs in by changing the '*tasks.md' pathspec and the '[x]' pattern below.
# Ticks live on the PLAN repo's change branch; the code repo is reported too. push-check runs in the cwd
# repo (git sets that to the repo being pushed), so the same hook can sit in both checkouts.
set -uo pipefail
. "$(dirname "$0")/lib/crew-env.sh"
state="${RUN_META_STATE:-/tmp/run-meta.env}"
times="${BG_DIR:-/tmp}/bg-times"
MAIN="${CREW_MAIN_BRANCH:-main}"

base_of() { git -C "$1" rev-parse --short "origin/$MAIN" 2>/dev/null || git -C "$1" rev-parse --short HEAD 2>/dev/null || echo none; }
# ticks added by commits of this run (HEAD --not origin/main: ticks other runs merged to main and this
# branch merged in are not ours) plus uncommitted ones.
count_ticks() { # <dir> <since-epoch>
  { git -C "$1" log --since="@$2" --no-merges -p HEAD --not "origin/$MAIN" -- '*tasks.md'; git -C "$1" diff HEAD -- '*tasks.md'; } 2>/dev/null | grep -c '^+.*\[x\]' || true
}
# repo_report <prefix> <dir> <base>: the branch/sha/commits/diff lines for one repo
repo_report() {
  local p="$1" d="$2" base="$3" head commits=0 stat=none
  head=$(git -C "$d" rev-parse --short HEAD 2>/dev/null || echo none)
  if [ "$base" != none ] && [ "$head" != none ]; then
    commits=$(git -C "$d" rev-list --count "$base..HEAD" 2>/dev/null || echo 0)
    stat=$(git -C "$d" diff --shortstat "$base" HEAD 2>/dev/null | sed 's/^ *//')
    [ -n "$stat" ] || stat="no changes"
  fi
  echo "  ${p}branch: $(git -C "$d" rev-parse --abbrev-ref HEAD 2>/dev/null || echo none)"
  echo "  ${p}base_sha: $base"
  echo "  ${p}head_sha: $head"
  echo "  ${p}commits: $commits"
  echo "  ${p}diff: \"$stat\""
}

case "${1:-}" in
  start)
    {
      echo "KIND=${2:-unknown}"
      echo "START_EPOCH=$(date -u +%s)"
      rm -f "$times"
      echo "BASE_CODE=$(base_of "$CREW_CODE_DIR")"
      echo "BASE_PLAN=$(base_of "$CREW_PLAN_DIR")"
    } > "$state"
    echo "run-meta: started ${2:-unknown}"
    ;;
  report)
    bash "$(dirname "$0")/agent-heartbeat.sh" stop 2>/dev/null || true
    if [ -f "$state" ]; then
      # shellcheck disable=SC1090
      . "$state"
    else
      # Never drop the block: a missing state file still yields session, branch and head.
      echo "run-meta: 'start' was not called; started/duration_s are unknown" >&2
      KIND=unknown; START_EPOCH=""; BASE_CODE=none; BASE_PLAN=none
    fi
    now=$(date -u +%s)
    session=$(env | grep -E '^CLAUDE_CODE_[A-Z_]*SESSION[A-Z_]*_ID=' | head -1 | cut -d= -f2- || true)
    mem_gb=$(awk '/MemTotal/ {printf "%.0f", $2/1048576}' /proc/meminfo 2>/dev/null || echo "?")
    cat <<EOT
run-metadata:
  kind: $KIND
  started: $( [ -n "$START_EPOCH" ] && { date -u -d "@$START_EPOCH" +%FT%TZ 2>/dev/null || date -u -r "$START_EPOCH" +%FT%TZ; } || echo unknown)
  finished: $(date -u +%FT%TZ)
  duration_s: $( [ -n "$START_EPOCH" ] && echo $((now - START_EPOCH)) || echo unknown)
  session: ${session:-unknown}
$(repo_report "" "$CREW_CODE_DIR" "$BASE_CODE")
$(repo_report "plan_" "$CREW_PLAN_DIR" "$BASE_PLAN")
  full_ci_s: "$(awk '$1=="ci"{printf "%s%ss exit %s", sep, $2, $3; sep=", "}' "$times" 2>/dev/null)"
  runner: "$(nproc 2>/dev/null || sysctl -n hw.ncpu) cpu, ${mem_gb} GB"
EOT
    ;;
  block)
    # One fenced block, never nested: agent fields (2-space indented YAML) come on stdin.
    echo '```yaml'
    bash "$0" report
    fields=""; if [ ! -t 0 ]; then fields=$(sed '/^```/d'); printf '%s\n' "$fields"; fi
    echo '```'
    # Never tick with `evaluator: n/a`: several worker runs did in practice.
    if grep -qE '^ *evaluator: *n/a' <<<"$fields"; then
      since=$(sed -n 's/^START_EPOCH=//p' "$state" 2>/dev/null || true)
      ticks=$(count_ticks "$CREW_PLAN_DIR" "${since:-$(date -u +%s)}")
      if [ "${ticks:-0}" -gt 0 ]; then echo "run-meta: WARN evaluator: n/a but this run ticked $ticks task(s): run the evaluator or untick before you push" >&2; fi
    fi
    # Worker runs were asked to plan the next change and ended without planning.
    if grep -q '^KIND=worker' "$state" 2>/dev/null && [ -f "$(dirname "$0")/worker-has-work.sh" ]; then
      asked=$(bash "$(dirname "$0")/worker-has-work.sh" 2>/dev/null || true)
      if grep -q 'plan the next one' <<<"$asked"; then echo "run-meta: WARN planning is still asked and no planning PR is open: do the worker prompt's planning step before you finish" >&2; fi
    fi
    ;;
  eval)
    case "${2:-}" in PASS|FAIL) echo "EVAL=$2" >> "$state" ;; *) echo "usage: $0 eval PASS|FAIL" >&2; exit 2 ;; esac
    ;;
  push-check)
    # The block WARN above came after the push, and runs still pushed ticks with `evaluator: n/a`
    # (observed). Refuse a push that ticks tasks unless `eval PASS` was recorded.
    [ -f "$state" ] || exit 0
    since=$(sed -n 's/^START_EPOCH=//p' "$state"); verdict=$(sed -n 's/^EVAL=//p' "$state" | tail -1)
    ticks=$(git log --since="@${since:-$(date -u +%s)}" --no-merges -p HEAD --not "origin/$MAIN" -- '*tasks.md' 2>/dev/null | grep -c '^+.*\[x\]' || true)
    if [ "${ticks:-0}" -gt 0 ] && [ "$verdict" != PASS ]; then
      echo "run-meta: push refused: this run ticked $ticks task(s) without an evaluator PASS. Run the independent evaluator, then 'bash $0 eval PASS', or untick." >&2
      exit 1
    fi
    ;;
  *) echo "usage: $0 start <kind> | report | block < agent-fields | eval PASS|FAIL | push-check" >&2; exit 2 ;;
esac
