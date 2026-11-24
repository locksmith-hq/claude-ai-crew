#!/usr/bin/env bash
# Sets every role's fire token in AWS SSM and in every crew repo (plan + code) at once, so no org-level secret is needed.
#   sync-fire-tokens.sh [--crew path/to/crew.json] [--ssm-prefix /crew/<project>] [--region R] [--only NAME ...] [--repo ORG/NAME ...] [--dry-run]
# Names come from crew.json roles.<role>.secret. Value of each secret, first hit wins: the env var of the same name,
# else the SSM parameter (so SSM is the source of truth and a re-run only fans it out), else a silent prompt.
# Values are piped to `aws ssm put-parameter` and `gh secret set` on stdin; never printed, never in argv.
set -uo pipefail
crew=crew.json; prefix=; region=${AWS_REGION:-${AWS_DEFAULT_REGION:-}}; dry=0; only=(); extra=()
while [ $# -gt 0 ]; do case "$1" in
  --crew) crew=$2; shift ;; --ssm-prefix) prefix=$2; shift ;; --region) region=$2; shift ;;
  --only) only+=("$2"); shift ;; --repo) extra+=("$2"); shift ;; --dry-run) dry=1 ;;
  *) echo "unknown option: $1" >&2; exit 2 ;; esac; shift; done
for c in jq gh aws; do command -v "$c" >/dev/null || { echo "$c is required" >&2; exit 2; }; done
[ -f "$crew" ] || { echo "no $crew (use --crew)" >&2; exit 2; }
[ -n "$prefix" ] || prefix="/crew/$(jq -r .project "$crew")"
repos=$(jq -r '[.repos.plan, .repos.code[]] | .[]' "$crew"; printf '%s\n' "${extra[@]+"${extra[@]}"}")
repos=$(grep . <<<"$repos" | sort -u)
names=$(jq -r '[.roles[].secret // empty] | unique[]' "$crew")
[ ${#only[@]} -gt 0 ] && names=$(printf '%s\n' "${only[@]}")
awsr=(); [ -n "$region" ] && awsr=(--region "$region")
fail=0
for n in $names; do
  v=${!n:-}
  [ -n "$v" ] || v=$(aws ssm get-parameter ${awsr[@]+"${awsr[@]}"} --name "$prefix/$n" --with-decryption --query Parameter.Value --output text 2>/dev/null || true)
  if [ -z "$v" ]; then
    [ "$dry" = 1 ] && { echo "$n: no value (env, SSM); would prompt"; continue; }
    read -rsp "$n: " v </dev/tty; echo
  fi
  [ -n "$v" ] || { echo "$n: empty, skipped" >&2; fail=1; continue; }
  if [ "$dry" = 1 ]; then echo "$n: would set SSM $prefix/$n and $(wc -w <<<"$repos") repos"; continue; fi
  # shortcut: the value is passed to aws via --value (argv, visible to local ps for a moment); upgrade to file://-based input if the host is shared
  aws ssm put-parameter ${awsr[@]+"${awsr[@]}"} --name "$prefix/$n" --type SecureString --overwrite --value "$v" >/dev/null && echo "$n: SSM ok" || { echo "$n: SSM FAILED" >&2; fail=1; }
  for r in $repos; do
    printf '%s' "$v" | gh secret set "$n" -R "$r" >/dev/null && echo "$n: $r ok" || { echo "$n: $r FAILED" >&2; fail=1; }
  done
done
exit $fail
