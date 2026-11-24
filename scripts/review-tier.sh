#!/usr/bin/env bash
# Which reviewer a PR's merge review needs, from its changed paths (one per line on stdin) and the plan repo's
# crew.json `review` block. Prints one line: `<tier> <model>`, or `skip` when no model review is needed.
#   review.tiers:        [{name, model, paths: [glob...], description}], strongest first; the first tier any
#                        changed path matches wins.
#   review.skip_globs:   [glob...]; when EVERY changed path matches, print `skip`. A `!glob` re-includes paths
#                        (last match wins), e.g. ["docs/", "!docs/agents/"].
#   review.default_tier: the tier for everything else (a tier name; its `paths` may be empty).
# Globs match the whole path with bash patterns, where `*` also crosses `/`; a leading `/` is ignored and a
# trailing `/` means the whole directory (the CODEOWNERS convention review.yml uses too).
# No `review.tiers` prints `default` and an empty model: the caller's own model is used, never a skip.
# An empty diff is reviewed (default tier). A bad config (unknown default tier, unsafe model id) exits 1, and
# review.yml then falls back to its strongest model.
#   scripts/review-tier.sh path/to/crew.json < files
set -euo pipefail
cfg=${1:?usage: review-tier.sh path/to/crew.json < changed-paths}
command -v jq >/dev/null || { echo "review-tier: jq is required" >&2; exit 2; }

match() { # <path> <glob>
  local g=${2#/}
  [[ "$g" == */ ]] && g="$g*"
  # shellcheck disable=SC2053
  [[ "$1" == $g ]]
}

files=()
while IFS= read -r f || [ -n "$f" ]; do [ -n "$f" ] && files+=("$f"); done

ntiers=$(jq '.review.tiers // [] | length' "$cfg")
[ "$ntiers" -gt 0 ] || { echo "default "; exit 0; }

tier_out() { # <index>: prints "<name> <model>", refusing a model id that could inject CLI arguments
  local name model
  name=$(jq -r --argjson i "$1" '.review.tiers[$i].name // ""' "$cfg")
  model=$(jq -r --argjson i "$1" '.review.tiers[$i].model // ""' "$cfg")
  [[ "$name" =~ ^[A-Za-z0-9_.-]+$ ]] || { echo "review-tier: tier $1 has a bad name '$name'" >&2; exit 1; }
  [[ "$model" =~ ^[A-Za-z0-9][A-Za-z0-9._:-]*$ ]] || { echo "review-tier: tier '$name' has a bad model '$model'" >&2; exit 1; }
  echo "$name $model"
}

# 1 the first (strongest) tier any changed path matches
for ((i = 0; i < ntiers; i++)); do
  globs=(); while IFS= read -r g; do globs+=("$g"); done < <(jq -r --argjson i "$i" '.review.tiers[$i].paths // [] | .[]' "$cfg")
  for f in "${files[@]+"${files[@]}"}"; do
    for g in "${globs[@]+"${globs[@]}"}"; do
      match "$f" "$g" && { tier_out "$i"; exit 0; }
    done
  done
done

# 2 skip when every path is a skip path (never on an empty diff)
skips=(); while IFS= read -r g; do skips+=("$g"); done < <(jq -r '.review.skip_globs // [] | .[]' "$cfg")
if [ "${#files[@]}" -gt 0 ] && [ "${#skips[@]}" -gt 0 ]; then
  all=1
  for f in "${files[@]}"; do
    s=0
    for g in "${skips[@]}"; do
      if [[ "$g" == '!'* ]]; then match "$f" "${g#!}" && s=0; else match "$f" "$g" && s=1; fi
    done
    [ "$s" = 1 ] || { all=0; break; }
  done
  [ "$all" = 1 ] && { echo skip; exit 0; }
fi

# 3 the default tier
d=$(jq -r '.review.default_tier // ""' "$cfg")
i=$(jq -r --arg d "$d" '[.review.tiers[].name] | index($d) // ""' "$cfg")
[ -n "$i" ] || { echo "review-tier: review.default_tier '$d' is not a tier name" >&2; exit 1; }
tier_out "$i"
