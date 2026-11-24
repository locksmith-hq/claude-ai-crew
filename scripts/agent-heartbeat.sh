#!/usr/bin/env bash
# Proof of life for the dispatcher (a worker lease is released as dead without it, once crew.json dispatch.heartbeat is on).
#   agent-heartbeat.sh start   post `<!-- run-start -->` on the agent-log issue, then re-edit it every
#                              CREW_HEARTBEAT_SECONDS (default 600) from a background loop; workers only, else a no-op
#   agent-heartbeat.sh beat    edit the comment once (the loop's step; also for tests)
#   agent-heartbeat.sh stop    stop the loop (run-meta.sh report calls it)
# The comment's updated_at is the heartbeat, so an edit must change the body: it carries the time. A dead VM stops the
# loop with it, which is the point: no heartbeat means no live run. State is under AGENT_ID_DIR (default ~/.config/crew-agent).
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/crew-env.sh
. "$here/lib/crew-env.sh"
dir="${AGENT_ID_DIR:-$HOME/.config/crew-agent}"; mkdir -p "$dir"
idf="$dir/heartbeat.id"; pidf="$dir/heartbeat.pid"
persona=${AGENT_PERSONA:-$(cat "$dir/persona" 2>/dev/null)}
body() { printf '<!-- run-start -->\nrun start %s, heartbeat %s\n' "$(cat "$dir/heartbeat.t0" 2>/dev/null)" "$(date -u +%FT%TZ)"; }

case "${1:-}" in
  start)
    case "$persona" in worker-*) ;; *) exit 0 ;; esac   # only dispatched workers are leased
    date -u +%FT%TZ > "$dir/heartbeat.t0"
    url=$(body | bash "$here/agent-comment.sh" log) || { echo "agent-heartbeat: run-start post failed (the dispatcher may release this lease)" >&2; exit 0; }
    id=${url##*issuecomment-}; [[ "$id" =~ ^[0-9]+$ ]] || { echo "agent-heartbeat: no comment id in '$url'" >&2; exit 0; }
    echo "$id" > "$idf"
    # setsid/nohup: the loop must outlive agent-start.sh. It ends with the VM, or `stop`.
    CREW_PLAN_DIR="$CREW_PLAN_DIR" AGENT_ID_DIR="$dir" AGENT_PERSONA="$persona" \
      nohup $(command -v setsid || true) bash -c 'while sleep "${CREW_HEARTBEAT_SECONDS:-600}"; do bash "$0" beat || true; done' "$here/agent-heartbeat.sh" >/dev/null 2>&1 &
    echo $! > "$pidf"
    echo "OK     heartbeat      run-start comment $id, every ${CREW_HEARTBEAT_SECONDS:-600}s"
    ;;
  beat)
    id=$(cat "$idf" 2>/dev/null) || exit 0
    (cd "$CREW_PLAN_DIR" && gh api -X PATCH "repos/$PLAN_REPO/issues/comments/$id" -f body="$(body)" >/dev/null)
    ;;
  stop)
    [ -f "$pidf" ] && kill "$(cat "$pidf")" 2>/dev/null
    rm -f "$pidf"
    ;;
  *) sed -n '3,6p' "$0" >&2; exit 2 ;;
esac
