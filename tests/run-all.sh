#!/usr/bin/env bash
# Runs every offline test and the repo checks. Used by CI and before every push.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
fail=0
for t in scripts/leak-check.test.sh tests/*.test.sh; do
  [ -f "$t" ] || continue
  echo "== $t"; bash "$t" || fail=1
done
echo "== leak-check"; bash scripts/leak-check.sh || fail=1
echo "== validate-pack"; bash scripts/validate-pack.sh examples/domain-pack/crew.json || fail=1
if command -v shellcheck >/dev/null 2>&1; then
  echo "== shellcheck"; shellcheck -S warning scripts/*.sh scripts/lib/*.sh tests/*.sh || fail=1
fi
[ "$fail" = 0 ] && echo "run-all: OK"
exit "$fail"
