#!/usr/bin/env bash
# Sets every role's fire token in AWS SSM and in every crew repo (plan + code), all or nothing.
#   sync-fire-tokens.sh [--crew path/to/crew.json] [--ssm-prefix /crew/<project>] [--region R] [--only NAME ...] [--repo ORG/NAME ...] [--dry-run]
# Names come from crew.json roles.<role>.secret. Value of each, first hit wins: env var of the same name, else the
# SSM parameter (SSM is the source of truth), else a silent prompt. Values go to aws/gh on stdin where possible; never printed.
# All-or-nothing: (1) every value is gathered, (2) preflight checks SSM and every repo accept writes, (3) SSM is written,
# then every repo; (4) on any failure everything written so far is rolled back (SSM to its previous value or deleted,
# repo secrets to that previous value, or deleted when there was none). A repo secret's old value is read from SSM,
# so rollback is exact when SSM was in sync; otherwise it says which secrets it could not restore.
set -uo pipefail
crew=crew.json; prefix=; region=${AWS_REGION:-${AWS_DEFAULT_REGION:-}}; dry=0; only=(); extra=()
while [ $# -gt 0 ]; do case "$1" in
  --crew) crew=$2; shift ;; --ssm-prefix) prefix=$2; shift ;; --region) region=$2; shift ;;
  --only) only+=("$2"); shift ;; --repo) extra+=("$2"); shift ;; --dry-run) dry=1 ;;
  *) echo "unknown option: $1" >&2; exit 2 ;; esac; shift; done
for c in jq gh aws; do command -v "$c" >/dev/null || { echo "$c is required" >&2; exit 2; }; done
[ -f "$crew" ] || { echo "no $crew (use --crew)" >&2; exit 2; }
[ -n "$prefix" ] || prefix="/crew/$(jq -r .project "$crew")"
repos=$({ jq -r '[.repos.plan, .repos.code[]] | .[]' "$crew"; printf '%s\n' ${extra[@]+"${extra[@]}"}; } | grep . | sort -u)
names=$(jq -r '[.roles[].secret // empty] | unique[]' "$crew")
[ ${#only[@]} -gt 0 ] && names=$(printf '%s\n' "${only[@]}")
awsr=(); [ -n "$region" ] && awsr=(--region "$region")
ssm() { aws ssm "$1" ${awsr[@]+"${awsr[@]}"} "${@:2}"; }
getp() { ssm get-parameter --name "$prefix/$1" --with-decryption --query Parameter.Value --output text 2>/dev/null; }

# (1) gather every value first; nothing is written until all are known
tmp=$(mktemp -d); chmod 700 "$tmp"; trap 'rm -rf "$tmp"' EXIT
for n in $names; do
  old=$(getp "$n" || true); [ -n "$old" ] && printf '%s' "$old" >"$tmp/$n.old"
  v=${!n:-}; [ -n "$v" ] || v=$old
  if [ -z "$v" ]; then
    [ "$dry" = 1 ] && { echo "$n: no value (env, SSM); would prompt"; continue; }
    read -rsp "$n: " v </dev/tty; echo
  fi
  [ -n "$v" ] || { echo "$n: empty value; nothing written" >&2; exit 1; }
  printf '%s' "$v" >"$tmp/$n.new"
done

# (2) preflight: every repo must accept secret writes and SSM must be reachable, before anything changes
bad=0
for r in $repos; do gh api "repos/$r/actions/secrets/public-key" >/dev/null 2>&1 || { echo "preflight: cannot write secrets in $r" >&2; bad=1; }; done
ssm describe-parameters --max-items 1 >/dev/null 2>&1 || { echo "preflight: SSM not reachable (aws credentials, region?)" >&2; bad=1; }
[ "$bad" = 0 ] || { echo "nothing written" >&2; exit 1; }
if [ "$dry" = 1 ]; then for n in $names; do echo "$n: would set SSM $prefix/$n and $(wc -w <<<"$repos" | tr -d ' ') repos"; done; exit 0; fi

# (3) write SSM, then every repo; remember each write for rollback
done_ssm=(); done_repo=()
put() { ssm put-parameter --name "$prefix/$1" --type SecureString --overwrite --value "file://$tmp/$1.new" >/dev/null; }
setr() { gh secret set "$1" -R "$2" <"$tmp/$1.new" >/dev/null; }
fail=
for n in $names; do put "$n" && done_ssm+=("$n") || { fail="SSM $n"; break; }; done
if [ -z "$fail" ]; then for n in $names; do for r in $repos; do
  setr "$n" "$r" && done_repo+=("$n $r") || { fail="$n in $r"; break 2; }
done; done; fi
[ -z "$fail" ] && { echo "ok: ${#done_ssm[@]} secrets in SSM and $(wc -w <<<"$repos" | tr -d ' ') repos"; exit 0; }

# (4) roll back
echo "FAILED at $fail; rolling back" >&2; lost=
for n in ${done_ssm[@]+"${done_ssm[@]}"}; do
  if [ -f "$tmp/$n.old" ]; then cp "$tmp/$n.old" "$tmp/$n.new"; put "$n" || lost="$lost SSM:$n"
  else ssm delete-parameter --name "$prefix/$n" >/dev/null || lost="$lost SSM:$n"; fi
done
for nr in ${done_repo[@]+"${done_repo[@]}"}; do
  n=${nr%% *}; r=${nr#* }
  if [ -f "$tmp/$n.old" ]; then setr "$n" "$r" || lost="$lost $n@$r"; else gh secret delete "$n" -R "$r" >/dev/null 2>&1 || lost="$lost $n@$r"; fi
done
[ -z "$lost" ] && echo "rolled back; nothing changed" >&2 || echo "ROLLBACK INCOMPLETE, fix by hand:$lost" >&2
exit 1
