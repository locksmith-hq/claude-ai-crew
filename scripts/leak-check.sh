#!/usr/bin/env bash
# Keeps project-specific identifiers and secrets out of this public, generic repo.
# Usage: scripts/leak-check.sh   (ROOT overrides the repo root, used by the tests)
# Checks tracked and unignored files against generic patterns, plus your own regexes (one per line,
# '#' comments) in the git-ignored .leak-denylist.local.
set -uo pipefail
ROOT="${ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT" || exit 2
fail=0
generic=(
  'sk-ant-[A-Za-z0-9_-]{10,}'            # Anthropic keys and OAuth tokens
  'gh[pousr]_[A-Za-z0-9]{20,}'            # GitHub tokens
  'AKIA[0-9A-Z]{16}'                      # AWS access key IDs
  '-----BEGIN [A-Z ]*PRIVATE KEY-----'    # private keys
  'trig_[0-9A-Za-z]{20,}'                 # real routine trigger ids (examples use trig_REPLACE_ME)
  'arn:aws:[a-z0-9-]*:[a-z0-9-]*:[0-9]{12}' # ARNs with a real account id
  '\.awsapps\.com'                        # SSO portal URLs
  '[A-Za-z0-9._%+-]+@gmail\.com'          # personal addresses
)
files="$(mktemp)"
{ if git rev-parse --git-dir >/dev/null 2>&1 && [ -z "${NO_GIT:-}" ]; then git ls-files -co --exclude-standard
  else find . -type f -not -path './.git/*' | sed 's#^\./##'; fi; } \
  | grep -vE '^(scripts/leak-check\.sh|scripts/leak-check\.test\.sh|\.leak-denylist\.local)$' \
  | while IFS= read -r f; do [ -f "$f" ] && printf '%s\0' "$f"; done > "$files"
scan() { # $1 = regex
  local hit
  while IFS= read -r hit; do [ -n "$hit" ] && { echo "leak-check FAIL: pattern '$1' in $hit" >&2; fail=1; }; done \
    < <(xargs -0 grep -IEl -e "$1" -- < "$files" 2>/dev/null)
}
for p in "${generic[@]}"; do scan "${p%%  *}"; done
if [ -f .leak-denylist.local ]; then
  while IFS= read -r p; do case "$p" in ''|'#'*) continue ;; esac; scan "$p"; done < .leak-denylist.local
fi
rm -f "$files"
[ "$fail" = 0 ] && echo "leak-check: OK"
exit "$fail"
