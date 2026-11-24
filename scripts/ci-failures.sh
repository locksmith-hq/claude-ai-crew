#!/usr/bin/env bash
# Why is CI red? Reads only what the API serves when job logs are blocked (the log blob host often is):
# failing check runs, their failed steps, their annotations (failing test names when CI emits them), and
# failing commit statuses (merge-ready). One call instead of a dozen hand-written `gh api` lines.
#   ci-failures.sh <pr-number | branch | sha> [-R owner/name]    (default repo: $CODE_REPO)
# Prints, then exits 0 when nothing failed, 1 when something did, 2 on usage or API errors:
#   PR #<n> is merged|closed: nothing to fix          (a stale wake-up: stop here)
#   CONFLICT: merge origin/<base> into <branch>        (the PR cannot merge)
#   FAIL <check> (<conclusion>) <url>
#     step: <failed step name>
#     <path>:<line> <level>: <message, first line>     (at most 20 per check)
#   FAIL status <context>: <description>
#   pending: <check>, ...
#   green                                              (nothing failed or pending)
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/crew-env.sh
. "$here/lib/crew-env.sh"
ref=""; repo="$CODE_REPO"
while [ $# -gt 0 ]; do case "$1" in -R) repo="${2:?}"; shift ;; -*) echo "ci-failures: unknown option $1" >&2; exit 2 ;; *) ref="$1" ;; esac; shift; done
[ -n "$ref" ] || { sed -n '5p' "$0" >&2; exit 2; }

if [[ "$ref" =~ ^[0-9]+$ ]]; then
  pr=$(gh api "repos/$repo/pulls/$ref") || { echo "ci-failures: cannot read PR #$ref in $repo" >&2; exit 2; }
  if [ "$(jq -r .state <<<"$pr")" = closed ]; then
    echo "PR #$ref is $(jq -r 'if .merged_at then "merged" else "closed" end' <<<"$pr"): nothing to fix"; exit 0
  fi
  sha=$(jq -r .head.sha <<<"$pr")
  [ "$(jq -r .mergeable_state <<<"$pr")" = dirty ] && echo "CONFLICT: merge origin/$(jq -r .base.ref <<<"$pr") into $(jq -r .head.ref <<<"$pr")"
else
  sha=$(gh api "repos/$repo/commits/$ref" -q .sha) || { echo "ci-failures: no commit for '$ref' in $repo" >&2; exit 2; }
fi

failed=0
runs=$(gh api "repos/$repo/commits/$sha/check-runs?per_page=100" -q '.check_runs[]|[.id, .name, .status, (.conclusion // ""), .html_url, .app.slug]|@tsv') \
  || { echo "ci-failures: cannot read check runs of $sha" >&2; exit 2; }
pending=""
while IFS=$'\t' read -r id name status concl link app; do
  [ -n "$id" ] || continue
  [ "$status" = completed ] || { pending="${pending:+$pending, }$name"; continue; }
  case "$concl" in failure|timed_out|cancelled|action_required|startup_failure) ;; *) continue ;; esac
  failed=1; echo "FAIL $name ($concl) $link"
  # An Actions check run id is its job id: the job's steps say where it died even when the log is unreadable.
  [ "$app" = github-actions ] && gh api "repos/$repo/actions/jobs/$id" -q '.steps[]? | select(.conclusion == "failure") | "  step: " + .name' 2>/dev/null
  gh api "repos/$repo/check-runs/$id/annotations?per_page=20" \
    -q '.[] | "  \(.path):\(.start_line) \(.annotation_level): \(.message | split("\n")[0])"' 2>/dev/null
done <<<"$runs"
statuses=$(gh api "repos/$repo/commits/$sha/status" -q '.statuses[] | select(.state == "failure" or .state == "error") | "FAIL status \(.context): \(.description // "")"' 2>/dev/null)
[ -n "$statuses" ] && { failed=1; echo "$statuses"; }
[ -n "$pending" ] && echo "pending: $pending"
[ "$failed" = 0 ] && [ -z "$pending" ] && echo green
exit "$failed"
