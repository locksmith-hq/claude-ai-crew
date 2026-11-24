#!/usr/bin/env bash
# A worker with nothing to take or plan asks for work: it opens one `needs-work` issue in the plan repo, which wakes
# the roles in crew.json channels.needs-work.to (PM and lead). They close it once a worker can take a change; closing
# wakes the worker. Skips while one is open, or when the newest one closed in the last 6h saw the same ready depth
# and blockers (ready-depth.sh) as now: nothing changed since that answer, so no hourly loop. Anything new blocked
# since then asks again.
#   scripts/request-work.sh [role] [reason]   (role defaults to AGENT_PERSONA, which is a role key in crew.json)
set -uo pipefail
. "$(dirname "$0")/lib/crew-env.sh"
AGENT_PERSONA=${AGENT_PERSONA:-$(cat "${AGENT_ID_DIR:-$HOME/.config/crew-agent}/persona" 2>/dev/null)}  # agent-identity.sh records it; later shells lose the export
role=${1:-${AGENT_PERSONA:-}}
[ -n "$role" ] || { echo "usage: request-work.sh <role> [reason] (or set AGENT_PERSONA)"; exit 2; }
why=${2:-no change to take, continue or plan}
open=$(gh api "repos/$PLAN_REPO/issues?labels=needs-work&state=open" -q length) || exit 1
[ "$open" -gt 0 ] && { echo "needs-work: already open"; exit 0; }
since=$(date -u -d '6 hours ago' +%FT%TZ 2>/dev/null || date -u -v-6H +%FT%TZ)
# Claimed changes come and go with worker runs; they are not news.
depth=$(bash "$(dirname "$0")/ready-depth.sh" | grep -v '^blocked: [^ ]* claimed') || exit 1
last=$(gh api "repos/$PLAN_REPO/issues?labels=needs-work&state=closed&since=$since&sort=updated&direction=desc&per_page=1" -q '.[0].body // ""') || exit 1
[ -n "$last" ] && [ "$(awk '/^```ready-depth$/{f=1; next} /^```$/{f=0} f' <<<"$last")" = "$depth" ] &&
  { echo "needs-work: answered within 6h and nothing changed since; not asking again"; exit 0; }
body=$(printf '<!-- agent -->\n<!-- raised-by: %s -->\n%s is idle: %s.\n\n- PM: which ready or plannable change can a worker take, or which change can be planned or split now?\n- Lead: which blocker below can you clear, or which evergreen change fills the gap?\n\nWhoever has a takeable change comments `Change: <id>`. Close this issue only once a worker can take a change; closing wakes %s.\n\n```ready-depth\n%s\n```\n' \
  "$role" "$role" "$why" "$role" "$depth")
gh api "repos/$PLAN_REPO/issues" -f title="Workers idle: $role has no work" -f body="$body" -f 'labels[]=needs-work' -q .html_url
