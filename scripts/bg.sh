#!/usr/bin/env bash
# Run a long command in the background with a hard timeout; poll it instead of blocking.
#   bg.sh start <name> <timeout-s> -- <cmd...>   start; log in $BG_DIR/bg-<name>.log (BG_DIR defaults to /tmp)
#   bg.sh wait  <name> [max-s]                    poll until done (max 110 s, under a typical 120 s tool
#                                                 limit; call again on exit 124); prints tail + exit code
#   bg.sh status <name>                           running | done <code>
# Each finished job appends "<name> <seconds> <exit>" to $BG_DIR/bg-times; run-meta.sh reports the `ci` rows.
# Low disk before a start: runs crew.json `.commands.free_disk` (a command that frees build caches) unless a
# process named `.commands.free_disk_skip_if_running` is alive. Both are optional; threshold BG_MIN_FREE_GB (8).
set -uo pipefail
. "$(dirname "$0")/lib/crew-env.sh"
cmd="${1:-}"; name="${2:-}"; [ -n "$cmd" ] && [ -n "$name" ] || { echo "usage: bg.sh start|wait|status <name> ..." >&2; exit 2; }
dir="${BG_DIR:-/tmp}"; log="$dir/bg-$name.log"; rc="$dir/bg-$name.rc"
case "$cmd" in
  start)
    t="${3:?timeout seconds}"; shift 3; [ "${1:-}" = "--" ] && shift
    rm -f "$rc"
    # Low disk: a build cache filled a worker's disk mid-run twice (observed). Free it only when no build runs.
    free_gb() { df -Pk . | awk 'NR==2{print int($4/1048576)}'; }
    freer=$(crew_get '.commands.free_disk'); busy=$(crew_get '.commands.free_disk_skip_if_running')
    if [ -n "$freer" ] && [ "$(free_gb)" -lt "${BG_MIN_FREE_GB:-8}" ] && { [ -z "$busy" ] || ! pgrep -x "$busy" >/dev/null; }; then
      (cd "$CREW_CODE_DIR" && bash -c "$freer") >/dev/null 2>&1
      echo "bg: low disk, ran free_disk: $(free_gb) GB free"
    fi
    # No stdin: a command that reads it (a stray `cat`) hung a worker run for 30 min.
    ( s=$(date +%s); timeout -s KILL "$t" "$@" </dev/null >"$log" 2>&1; c=$?
      e=$(( $(date +%s) - s ))
      # GNU timeout exits 124 when it kills the job; BSD/macOS timeout exits 137. Report one code (137) for both.
      [ "$c" = 124 ] && [ "$e" -ge "$t" ] && c=137
      echo "$name $e $c" >>"$dir/bg-times"; echo $c >"$rc" ) </dev/null >/dev/null 2>&1 &
    # The subshell above must not hold our stdout: `bg.sh start ... | tail` blocked until the job ended.
    echo "bg: started $name (timeout ${t}s), log $log"
    ;;
  status)
    if [ -f "$rc" ]; then echo "done $(cat "$rc")"; else echo running; fi
    ;;
  wait)
    max="${3:-110}"; [ "$max" -gt 110 ] && max=110; waited=0
    while [ ! -f "$rc" ] && [ "$waited" -lt "$max" ]; do sleep 1; waited=$((waited+1)); done
    tail -n 30 "$log" 2>/dev/null
    if [ -f "$rc" ]; then code=$(cat "$rc"); note=""; [ "$code" = 137 ] && note=" (killed by timeout)"; echo "bg: $name exited ${code}${note}"; exit "$code"
    else echo "bg: $name still running after ${max}s (wait again in a NEW call: a loop of waits passes the tool limit)"; exit 124; fi
    ;;
  *) echo "usage: bg.sh start|wait|status <name> ..." >&2; exit 2 ;;
esac
