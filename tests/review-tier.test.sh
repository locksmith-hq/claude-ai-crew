#!/usr/bin/env bash
# Tests for scripts/review-tier.sh (reviewer tier from changed paths and crew.json review.tiers), plus the
# merge-ready status strings review.yml sets and route.sh matches.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; R="$HERE/.."; pass=0; failn=0
ok() { echo "ok   $1"; pass=$((pass+1)); }; no() { echo "FAIL $1"; failn=$((failn+1)); }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
jq '.review += {
  tiers: [
    {name: "strong", model: "claude-opus-5-5", description: "secrets and the trust root",
     paths: ["core/secrets/", "/.github/", "AGENTS.md"]},
    {name: "standard", model: "claude-sonnet-5-5", description: "other code", paths: []}],
  default_tier: "standard",
  skip_globs: ["docs/", "changes/", "!docs/agents/", "!*/tasks.md"]}' "$R/examples/domain-pack/crew.json" >"$W/crew.json"

t() { # <want> <paths, \n-separated> [config]
  local got; got=$(printf '%b' "$2" | bash "$R/scripts/review-tier.sh" "${3:-$W/crew.json}" 2>/dev/null) || got="exit$?"
  [ "$got" = "$1" ] && ok "$1 <- ${2//\\n/ }" || no "want '$1' got '$got' <- ${2//\\n/ }"
}
t 'strong claude-opus-5-5' 'core/secrets/vault.rs'                      # secrets path -> strongest tier
t 'strong claude-opus-5-5' 'docs/a.md\ncore/secrets/x/y.rs'             # one risky path is enough
t 'strong claude-opus-5-5' '.github/workflows/ci.yml'                   # leading / in a glob is ignored
t 'strong claude-opus-5-5' 'AGENTS.md'
t 'standard claude-sonnet-5-5' 'sub/AGENTS.md'                          # a glob matches the whole path
t 'skip' 'docs/guide.md'                                                # docs only -> no model review
t 'skip' 'docs/a.md\nchanges/x/proposal.md\nchanges/x/specs/a/spec.md'
t 'standard claude-sonnet-5-5' 'app/src/main.ts'                        # code -> default tier
t 'standard claude-sonnet-5-5' 'unknown/path/file.xyz'                  # unknown path -> default tier
t 'standard claude-sonnet-5-5' 'docs/a.md\napp/x.ts'                    # mixed docs and code -> default
t 'standard claude-sonnet-5-5' 'docs/agents/owner.md'                   # !glob keeps a skip path reviewed
t 'standard claude-sonnet-5-5' 'changes/x/tasks.md'                     # ticks claim verified work
t 'standard claude-sonnet-5-5' ''                                       # empty diff is reviewed, never skipped

# no tiers: today's behaviour (the caller's model, never a skip)
jq 'del(.review.tiers, .review.default_tier) | .review.skip_globs = ["docs/"]' "$W/crew.json" >"$W/none.json"
t 'default ' 'docs/a.md' "$W/none.json"
# a bad config fails, so review.yml falls back to its strongest model
jq '.review.default_tier = "missing"' "$W/crew.json" >"$W/bad-default.json"
t 'exit1' 'app/x.ts' "$W/bad-default.json"
jq '.review.tiers[0].model = "x --allowedTools Bash"' "$W/crew.json" >"$W/bad-model.json"
t 'exit1' 'core/secrets/a.rs' "$W/bad-model.json"
for f in bad-default bad-model; do
  bash "$R/scripts/validate-pack.sh" "$W/$f.json" >/dev/null 2>&1 && no "validate-pack accepts $f" || ok "validate-pack rejects $f"
done

# the merge-ready strings route.sh matches are the ones review.yml sets
for s in 'Claude review FAIL' 'owned paths' 'unchecked tasks'; do
  if grep -qF "st failure \"$s" "$R/.github/workflows/review.yml" && grep -qF "\"$s\"*" "$R/scripts/route.sh"
  then ok "status '$s' set by review.yml and matched by route.sh"; else no "status '$s' out of sync"; fi
done
grep -qF 'bash .crew/harness/scripts/review-tier.sh .crew/plan/crew.json' "$R/.github/workflows/review.yml" \
  && ok "review.yml runs the harness tier script on the plan repo config" || no "review.yml does not run review-tier.sh"

echo "review-tier.test: $pass passed, $failn failed"
[ "$failn" = 0 ]
