#!/usr/bin/env bash
# Post an agent comment on an issue or PR, as your App, with the markers the routing needs:
#   agent-comment.sh plan|code <number> < body
#   agent-comment.sh log < body       (the plan repo's agent-log issue, crew.json issues.agent_log)
# - adds `<!-- agent -->` as the first line and `<!-- role: <persona> -->` after it when missing (the dispatcher
#   ends a worker's lease from the role marker; without it the worker stays busy for 2 hours);
# - posts from inside the plan or code checkout, where the gh shim gives your App token (elsewhere it would post
#   as the owner);
# - then checks the author (agent-identity.sh verify-author) when agent-start.sh recorded a persona.
# Prints the comment URL. Exit: 0 posted, 1 posted under the wrong login (stop, open a harness issue), 2 usage or
# post failure.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/crew-env.sh
. "$here/lib/crew-env.sh"
usage() { sed -n '3,4p' "$0" >&2; exit 2; }
case "${1:-}" in
  plan) repo=$PLAN_REPO; dir=$CREW_PLAN_DIR; n=${2:-} ;;
  code) repo=$CODE_REPO; dir=$CREW_CODE_DIR; n=${2:-} ;;
  log)  repo=$PLAN_REPO; dir=$CREW_PLAN_DIR; n=$(crew_get '.issues.agent_log') ;;
  *) usage ;;
esac
[[ "$n" =~ ^[0-9]+$ ]] || usage
body=$(cat)
[ -n "${body//[[:space:]]/}" ] || { echo "agent-comment: empty body on stdin" >&2; exit 2; }
idfile="${AGENT_ID_DIR:-$HOME/.config/crew-agent}/persona"   # written by agent-start.sh
persona=${AGENT_PERSONA:-$(cat "$idfile" 2>/dev/null)}
grep -q '<!-- role: ' <<<"$body" || { [ -n "$persona" ] && body=$(printf '<!-- role: %s -->\n%s' "$persona" "$body"); }
[ "$(head -1 <<<"$body")" = '<!-- agent -->' ] || body=$(printf '<!-- agent -->\n%s' "$(grep -vxF '<!-- agent -->' <<<"$body")")
link=$(cd "$dir" && gh api "repos/$repo/issues/$n/comments" -f body="$body" -q .html_url) || { echo "agent-comment: posting on $repo#$n failed" >&2; exit 2; }
echo "$link"
[ -f "$idfile" ] || exit 0
bash "$here/agent-identity.sh" verify-author "$link"; [ $? = 1 ] && exit 1
exit 0
