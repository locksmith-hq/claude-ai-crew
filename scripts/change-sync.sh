#!/usr/bin/env bash
# Rewrites each change's tracking issue as its status page: state, PR, dependencies, anything waiting
# on the owner (a parked change opens with why and who moves next), the summary, every task with its
# tick, and the last progress entry. Sets one `status:<state>` label (the Project board filters on it;
# a parked change gets status:parked-owner or status:parked-stuck). Archived changes get status:done and close.
# tasks.md stays the source of truth; agents never edit these issues by hand.
#   scripts/change-sync.sh            all open changes, plus archived ones whose issue is still open
#   DRY_RUN=1 scripts/change-sync.sh  print the bodies instead of writing them
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/crew-env.sh
. "$here/lib/crew-env.sh"
# Plan files are read from the plan repo working tree; git reads go through crew_plan_git.
cd "$CREW_PLAN_DIR" || exit 1; CREW_PLAN_DIR=$PWD
CH=${PATH_CHANGES%/}

# shellcheck source=scripts/issue-lib.sh
. "$here/issue-lib.sh"

# Org issue fields (text) on a parked or blocked change: "Parked Reason" (Waiting on owner | Stuck |
# Waiting on <dep>) and "Parked Link" (the blocker or dependency issue); cleared in every other state. Writes only differences.
# The Actions token cannot list org issue fields (observed in practice); then the fields are skipped.
# shortcut: run with a token that can read org issue fields, or skip the park fields.
park_ids=$(gh api "orgs/${PLAN_REPO%%/*}/issue-fields" -q '.[]|"\(.name)\t\(.id)"' 2>/dev/null) || park_ids=""
F_REASON=$(awk -F'\t' '$1=="Parked Reason"{print $2}' <<<"$park_ids"); F_LINK=$(awk -F'\t' '$1=="Parked Link"{print $2}' <<<"$park_ids")
park_fields() { # <issue> <reason> <link>; empty values clear
  [ -n "$F_REASON" ] && [ -n "$F_LINK" ] && [ "${DRY_RUN:-0}" != 1 ] || return 0
  local cur f want
  cur=$(gh api "repos/$PLAN_REPO/issues/$1/issue-field-values" -q '.[]|"\(.issue_field_id)\t\(.value)"') || return 0
  for f in "$F_REASON	$2" "$F_LINK	$3"; do
    want=${f#*$'\t'}; f=${f%%$'\t'*}
    [ "$(awk -F'\t' -v f="$f" '$1==f{print $2}' <<<"$cur")" = "$want" ] && continue
    if [ -n "$want" ]; then gh api -X POST "repos/$PLAN_REPO/issues/$1/issue-field-values" \
      --input - <<<"{\"issue_field_values\":[{\"field_id\":$f,\"value\":$(jq -Rn --arg v "$want" '$v')}]}" >/dev/null
    else gh api -X DELETE "repos/$PLAN_REPO/issues/$1/issue-field-values/$f" >/dev/null; fi || echo "park fields: could not update #$1"
  done
}

# The top of a parked change's page: why it waits and who moves next, in plain words.
parked_block() { # <owner|rescue> <blocker-issue> <id>
  local j title why
  j=$(gh api "repos/$PLAN_REPO/issues/$2" 2>/dev/null) || j='{}'
  title=$(jq -r '.title // ""' <<<"$j")
  # First sentence of the blocker's first real line (skips the agent marker, blank and "Change:" lines).
  why=$(jq -r '.body // ""' <<<"$j" | grep -vE '^\s*(<!--|$|Change:)' | head -1 | sed -E 's/([.!?]) .*/\1/' | cut -c1-240)
  if [ "$1" = owner ]; then
    echo "## ⏸ Parked: waiting for owner approval"; echo
    echo "- **Why:** ${why:-$title}"
    echo "- **You:** open #$2, pick an option or reply \`approved\`."
    echo "- **Meanwhile:** workers continue on other changes."
  else
    echo "## ⏸ Parked: waiting for the lead"; echo
    echo "- **On:** $title (#$2)"
    echo "- **Why:** ${why:-see #$2}"
    echo "- **Next:** the lead was woken to fix or decide it; closing #$2 wakes a worker. Only the lead brings it to you, as a \`needs-owner\` issue."
    echo "- **You:** nothing yet."
  fi
  echo
}

render() { # <id> <state> <detail>
  local id=$1 state=$2 detail=$3 src pr owner rescue
  src=$(crew_plan_git show "origin/claude/change-$id:$CH/$id/tasks.md" >/dev/null 2>&1 && echo "origin/claude/change-$id" || echo HEAD)
  pr=$(gh pr list -R "$CODE_REPO" --head "claude/change-$id" --state open --json number,isDraft,autoMergeRequest \
    -q '.[0]|select(.!=null)|"#\(.number)\(if .autoMergeRequest then " (auto-merge on)" else "" end)"' 2>/dev/null)
  owner=$(gh api "repos/$PLAN_REPO/issues?labels=needs-owner&state=open&per_page=100" \
    -q ".[]|select((.title+\" \"+(.body // \"\"))|contains(\"$id\"))|\"- ⚠ **Needs owner:** #\(.number) \(.title)\"" 2>/dev/null)
  rescue=$(gh api "repos/$PLAN_REPO/issues?labels=needs-rescue&state=open&per_page=100" \
    -q ".[]|select((.title+\" \"+(.body // \"\"))|contains(\"$id\"))|\"- Rescue in progress: #\(.number) \(.title)\"" 2>/dev/null)
  echo "**Status:** \`$state\`${detail:+ ($detail)} · **PR:** ${pr:-none yet} · **Depends on:** $(sed -nE 's/^x-depends_on:[[:space:]]*\[(.*)\]/\1/p' "$CH/$id/.openspec.yaml" 2>/dev/null || true)"
  echo
  if [ "$state" = parked ]; then parked_block "${detail%% *}" "${detail##*#}" "$id"
  elif [ -n "$owner$rescue" ]; then printf '%s\n%s\n\n' "$owner" "$rescue" | grep -v '^$'; echo; fi
  echo "## Summary"
  crew_plan_git show "$src:$CH/$id/proposal.md" 2>/dev/null | awk '/^## Why/{f=1;next} /^## /{f=0} f' | sed '/^$/d' | head -8
  links=$(crew_plan_git show "$src:$CH/$id/proposal.md" "$src:$CH/$id/design.md" 2>/dev/null | grep -oE 'https://claude\.ai/(code/)?artifact/[A-Za-z0-9_-]+' | sort -u | paste -sd' ' - || true)
  echo; echo "Brief: ${links:-none} · [proposal](../blob/main/$CH/$id/proposal.md) · [design](../blob/main/$CH/$id/design.md)"
  t=$(crew_plan_git show "$src:$CH/$id/tasks.md" 2>/dev/null)
  echo; echo "## Tasks ($(grep -cE '^\s*- \[[xX]\]' <<<"$t")/$(grep -cE '^\s*- \[[ xX]\]' <<<"$t") done)"
  grep -E '^(## |\s*- \[)' <<<"$t" | awk '/^## /{print ""; sub(/^## /, "### ")} 1'
  echo; echo "## Last progress"
  crew_plan_git show "$src:$CH/$id/progress.md" 2>/dev/null | awk '/^## [0-9]/{buf=""} {buf=buf $0 "\n"} END{printf "%s", buf}' | grep -v '^$' | head -8
  echo; echo "<!-- change-sync: generated from tasks.md and progress.md; edits here are overwritten -->"
}

# Linked pull requests: the change's PR gets a managed block with a closing keyword for the change
# issue, so it lists the PR under Development and closes when it merges (the finishing PR also archives the change, so closing then is correct).
link_pr() { # <id> <change-issue>
  local pr cur block new
  pr=$(gh api "repos/$CODE_REPO/pulls?head=${CODE_REPO%%/*}:claude/change-$1&state=open" -q '.[0].number // empty')
  [ -n "$pr" ] || return 0
  block=$(printf '<!-- issue-links:start -->\n---\nCloses %s#%s\n<!-- issue-links:end -->' "$PLAN_REPO" "$2")
  cur=$(gh api "repos/$CODE_REPO/pulls/$pr" -q '.body // ""')
  new=$(awk '/<!-- issue-links:start -->/{skip=1} !skip{print} /<!-- issue-links:end -->/{skip=0}' <<<"$cur")
  new=$(printf '%s\n\n%s' "$new" "$block")
  [ "$(awk '/<!-- issue-links:start -->/,/<!-- issue-links:end -->/' <<<"$cur")" = "$block" ] && return 0
  # GitHub ignores closing keywords written by the Actions token, so write with the automation PAT
  # (needs Pull requests: Read and write); fall back so the block is at least present.
  { [ -n "${GH_AUTOMATION_TOKEN:-}" ] && GH_TOKEN=$GH_AUTOMATION_TOKEN gh api -X PATCH "repos/$CODE_REPO/pulls/$pr" -f body="$new" >/dev/null 2>&1; } ||
    { echo "links: PAT could not edit PR #$pr; links will not register (GH_AUTOMATION_TOKEN needs Pull requests: Read and write)"
      gh api -X PATCH "repos/$CODE_REPO/pulls/$pr" -f body="$new" >/dev/null; } || echo "links: could not update PR #$pr"
}

bash "$here/change-status.sh" | while IFS=$'\t' read -r id state detail; do
  body=$(render "$id" "$state" "$detail")
  if [ "${DRY_RUN:-0}" = 1 ]; then printf '===== %s\n%s\n' "$id" "$body"; continue; fi
  n=$(bash "$here/change-issue.sh" "$id") || continue
  # The label and the Parked Reason / Parked Link issue fields say why a change is parked or blocked.
  lstate=$state; [ "$state" = parked ] && { [ "${detail%% *}" = owner ] && lstate=parked-owner || lstate=parked-stuck; }
  # The title follows the proposal, so an issue opened by a planner's lock gets its real name.
  title=$(sed -nE '1s/^# *(Proposal: *)?//p' "$CH/$id/proposal.md" 2>/dev/null)
  gh api -X PATCH "repos/$PLAN_REPO/issues/$n" -f title="$id: ${title:-$id}" -f body="$body" -f state=open >/dev/null && label "$n" "$lstate" && board "$n" "$lstate"
  if [ "$state" = parked ]; then park_fields "$n" "$([ "${detail%% *}" = owner ] && echo "Waiting on owner" || echo Stuck)" \
    "https://github.com/$PLAN_REPO/issues/${detail##*#}"
  elif [ "$state" = blocked ]; then dep=${detail#needs }; dn=$(bash "$here/change-issue.sh" "$dep" --find)
    park_fields "$n" "Waiting on $dep" "${dn:+https://github.com/$PLAN_REPO/issues/$dn}"
  else park_fields "$n" "" ""; fi
  link_pr "$id" "$n"
done

# Archived changes: mark done and close their issue.
for d in "$CH"/archive/*/; do
  id=$(basename "$d" | sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}-//')
  n=$(bash "$here/change-issue.sh" "$id" --find) || continue
  [ "$(gh api "repos/$PLAN_REPO/issues/$n" -q .state)" = open ] || continue
  [ "${DRY_RUN:-0}" = 1 ] && { echo "===== $id: would close #$n as done"; continue; }
  label "$n" "done"; board "$n" "done"; gh api -X PATCH "repos/$PLAN_REPO/issues/$n" -f state=closed -f state_reason=completed >/dev/null
done
