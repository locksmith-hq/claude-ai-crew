#!/usr/bin/env bash
# Push the current branch once and make sure it has an open PR. Run it from inside the checkout you push (plan or
# code repo), so the gh shim acts as your App. It does every pre-push check the rules ask for, so you don't:
#   push-pr.sh [--base <branch>] [--title <text>] [--body-file <file>] [--label <name>]...
#   1. refuses anything but a claude/* branch;
#   2. the branch's PR is merged or closed: moves the commits main lacks (by patch id, merges skipped) to <branch>-r<n> from
#      origin/main and pushes that instead (never to a merged PR's branch);
#   3. origin/<branch> has commits you lack (another session pushed): stops, exit 4, so you look before merging;
#   4. a stacked base branch whose PR already merged: retargets to main;
#   5. in the plan checkout, runs check-task-edits.sh before the push, not after CI;
#   6. git push -u (never force), then opens a non-draft PR labelled in-progress (plus --label) whose body ends
#      with the attribution line, or prints the open one. Last line: "PR #<n> <url>".
# Exit: 0 pushed, 2 usage or not a claude/* branch, 3 push or API failure, 4 remote ahead, 5 guard failed,
#       6 rebranch cherry-pick conflicted (aborted; nothing pushed).
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/crew-env.sh
. "$here/lib/crew-env.sh"
MAIN="${CREW_MAIN_BRANCH:-main}"
FOOTER="Generated with Claude Code"
die() { echo "push-pr: $2" >&2; exit "$1"; }

base=""; title=""; body_file=""; labels=(in-progress)
while [ $# -gt 0 ]; do case "$1" in
  --base) base="${2:?}"; shift ;; --title) title="${2:?}"; shift ;; --body-file) body_file="${2:?}"; shift ;;
  --label) labels+=("${2:?}"); shift ;; *) die 2 "unknown option: $1" ;; esac; shift; done

top=$(git rev-parse --show-toplevel 2>/dev/null) || die 2 "not in a git checkout"
branch=$(git rev-parse --abbrev-ref HEAD)
case "$branch" in claude/*) ;; *) die 2 "'$branch' is not a claude/* branch; agents push only to claude/*" ;; esac
url=$(git config --get remote.origin.url); repo=${url%.git}; repo=${repo#*github.com[:/]}
[[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die 2 "cannot read owner/name from origin ($url)"
org=${repo%%/*}
git fetch -q origin "$MAIN" 2>/dev/null || die 3 "git fetch origin $MAIN failed"
git fetch -q origin "$branch" 2>/dev/null || true   # a new branch has no remote yet

# pr_json <branch>: the newest PR for that head branch, any state ("" if none)
pr_json() { gh api "repos/$repo/pulls?head=$org:$1&state=all&sort=created&direction=desc&per_page=1" -q '.[0] // empty'; }

# 2. Merged or closed PR: never push there again. Rebranch the commits main lacks.
pr=$(pr_json "$branch") || die 3 "cannot read PRs of $repo"
if [ -n "$pr" ] && [ "$(jq -r .state <<<"$pr")" = closed ]; then
  old=$(jq -r .number <<<"$pr"); n=2
  while git ls-remote --exit-code -q origin "refs/heads/$branch-r$n" >/dev/null 2>&1 || git rev-parse -q --verify "refs/heads/$branch-r$n" >/dev/null; do n=$((n + 1)); done
  picks=$(git rev-list --reverse --no-merges --cherry-pick --right-only "origin/$MAIN...HEAD")
  [ -n "$picks" ] || die 0 "PR #$old is $(jq -r 'if .merged_at then "merged" else "closed" end' <<<"$pr") and main already has every commit; nothing to push"
  echo "push-pr: PR #$old is closed or merged; moving $(wc -l <<<"$picks" | tr -d " ") commit(s) to $branch-r$n from origin/$MAIN"
  git switch -q -c "$branch-r$n" "origin/$MAIN" || die 3 "cannot create $branch-r$n"
  # shellcheck disable=SC2086  # one sha per word
  if ! git cherry-pick $picks >/dev/null 2>&1; then
    git cherry-pick --abort 2>/dev/null; git switch -q "$branch"; git branch -q -D "$branch-r$n"
    die 6 "cherry-pick onto origin/$MAIN conflicted; aborted. Resolve by hand: git switch -c $branch-r$n origin/$MAIN && git cherry-pick $(echo $picks)"
  fi
  [ -n "$body_file" ] || { body_file=$(mktemp); printf 'Follows #%s, which was closed or merged before these commits landed.\n' "$old" >"$body_file"; }
  branch="$branch-r$n"; pr=""
fi

# 3. Another session pushed to this branch: look before you merge (it may be the same fix).
if git rev-parse -q --verify "refs/remotes/origin/$branch" >/dev/null; then
  ahead=$(git rev-list --count "HEAD..origin/$branch")
  [ "$ahead" = 0 ] || die 4 "origin/$branch has $ahead commit(s) you don't have (another session pushed). Read them: git log HEAD..origin/$branch; then git merge --no-edit origin/$branch, or drop your duplicate work"
fi

# 4. Base: --base, else the open PR's, else main. A stacked base whose PR merged becomes main.
[ -n "$base" ] || base=$(jq -r '.base.ref // empty' <<<"$pr"); [ -n "$base" ] || base=$MAIN
if [ "$base" != "$MAIN" ] && [ "$(pr_json "$base" | jq -r '.merged_at // empty')" != "" ]; then
  echo "push-pr: base $base is already merged; using $MAIN"; base=$MAIN
  [ -n "$pr" ] && { gh api -X PATCH "repos/$repo/pulls/$(jq -r .number <<<"$pr")" -f base="$MAIN" >/dev/null || die 3 "cannot retarget the PR to $MAIN"; }
fi

# 5. The task-edit and agent-system guard fails in CI otherwise; run it now (plan checkout only).
if [ "$(cd "$top" && pwd -P)" = "$(cd "$CREW_PLAN_DIR" && pwd -P)" ] && [ -f "$here/check-task-edits.sh" ]; then
  BRANCH="$branch" GUARD_DIR="$top" bash "$here/check-task-edits.sh" || die 5 "check-task-edits.sh failed; fix it before pushing"
fi

# 6. Push, then the PR.
git push -q -u origin "HEAD:refs/heads/$branch" || die 3 "git push failed"
if [ -n "$pr" ] && [ "$(jq -r .state <<<"$pr")" = open ]; then
  echo "pushed $branch"; echo "PR #$(jq -r .number <<<"$pr") $(jq -r .html_url <<<"$pr")"; exit 0
fi
[ -n "$title" ] || title=$(git log -1 --format=%s)
if [ -n "$body_file" ]; then body=$(cat "$body_file") || die 2 "cannot read $body_file"
else body=$(git log --reverse --format='- %s' "origin/$base..HEAD"); fi
grep -qF "$FOOTER" <<<"$body" || body=$(printf '%s\n\n%s' "$body" "$FOOTER")
new=$(gh api "repos/$repo/pulls" -f title="$title" -f head="$branch" -f base="$base" -F draft=false -f body="$body" -q '[.number, .html_url]|@tsv') \
  || die 3 "pushed $branch, but opening the PR failed"
num=${new%%$'\t'*}
args=(); for l in "${labels[@]}"; do args+=(-f "labels[]=$l"); done
gh api "repos/$repo/issues/$num/labels" "${args[@]}" >/dev/null || echo "push-pr: WARN could not add labels ${labels[*]} to #$num"
echo "pushed $branch"; echo "PR #$num ${new#*$'\t'}"
