#!/usr/bin/env bash
# Is there enough takeable work that no worker idles? First step of every PM and lead run.
#   depth=<n> target=<n> evergreen=<n> ok|LOW
#   blocked: <id> <state> <detail>      one line per open change a worker cannot take now
# depth: ready or stackable changes (change-status.sh); target: workers (crew.json dispatch.workers, else the
# worker-* roles) plus one; evergreen: ready changes marked `x-evergreen: true` in their .openspec.yaml (owner-free
# maintenance work the lead keeps in the pool). LOW when depth < target or evergreen < 2.
# Changes in review or finished are not listed: they need no unblocking.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/crew-env.sh
. "$here/lib/crew-env.sh"
CH=${PATH_CHANGES%/}
status=$(bash "$here/change-status.sh") || exit 1
workers=$(jq -r '(.dispatch.workers // []) | length' "$CREW_CONFIG")
[ "$workers" -gt 0 ] || workers=$(jq -r '[.roles // {} | keys[] | select(startswith("worker"))] | length' "$CREW_CONFIG")
target=$((workers + 1)); depth=0; evergreen=0; blocked=""
while IFS=$'\t' read -r id state detail; do
  [ -n "$id" ] || continue
  case "$state" in
    ready|stackable) depth=$((depth + 1))
      grep -qE '^x-evergreen:[[:space:]]*true[[:space:]]*$' "$CREW_PLAN_DIR/$CH/$id/.openspec.yaml" 2>/dev/null && evergreen=$((evergreen + 1)) ;;
    review|finished) ;;
    *) blocked+="blocked: $id $state${detail:+ $detail}"$'\n' ;;
  esac
done <<<"$status"
verdict=ok; { [ "$depth" -lt "$target" ] || [ "$evergreen" -lt 2 ]; } && verdict=LOW
echo "depth=$depth target=$target evergreen=$evergreen $verdict"
printf '%s' "$blocked"
