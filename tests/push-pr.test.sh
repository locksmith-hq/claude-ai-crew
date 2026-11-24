#!/usr/bin/env bash
# Tests for scripts/push-pr.sh: a local bare origin and a stubbed `gh` (PR fixtures per head branch; writes logged).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; pass=0; failn=0
ok() { echo "ok   $1"; pass=$((pass+1)); }; no() { echo "FAIL $1"; failn=$((failn+1)); }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
mkdir -p "$t/scripts/lib" "$t/bin" "$t/fx" "$t/plan"
cp "$HERE/../scripts/push-pr.sh" "$t/scripts/"; cp "$HERE/../scripts/lib/crew-env.sh" "$t/scripts/lib/"
jq '.repos.plan="acme/plan" | .repos.code=["acme/app"]' "$HERE/../examples/domain-pack/crew.json" >"$t/plan/crew.json"
cat >"$t/bin/gh" <<'EOF'
#!/usr/bin/env bash
# gh api <url> [-X M] [-f k=v]... [-q filter]: reads come from $FX/<head branch with / as _>.json, writes are logged
shift; url=$1; shift; q=.; w=""
while [ $# -gt 0 ]; do case "$1" in -q) q=$2; shift ;; -f|-F|-X) w="$w $1 $2"; shift ;; esac; shift; done
[ -n "$w" ] && echo "$url$w" >>"$FX/log"
case "$url" in
  *'pulls?head='*) h=${url#*head=*:}; h=${h%%&*}; f="$FX/${h//\//_}.json"; [ -f "$f" ] || f=/dev/null; jq -r "$q" <(cat "$f" 2>/dev/null || echo '[]') ;;
  */pulls) [ -n "$w" ] && jq -rn '{number: 7, html_url: "https://example.test/pull/7"}' | jq -r "$q" ;;
  *) echo '{}' ;;
esac
EOF
chmod +x "$t/bin/gh"
g() { git -c user.name=t -c user.email=t@example.test "$@"; }
reset() { # fresh origin with main + one commit, a clone on branch claude/x with one more commit
  rm -rf "$t/origin" "$t/app" "$t/fx"/*; mkdir -p "$t/origin/github.com/acme"
  git init -q --bare -b main "$t/origin/github.com/acme/app.git"
  g clone -q "$t/origin/github.com/acme/app.git" "$t/app" 2>/dev/null
  (cd "$t/app" && g commit -q --allow-empty -m base && git push -q origin HEAD:main && git switch -q -c claude/x && echo a >a && git add a && g commit -q -m "add a")
}
run() { (cd "$t/app" && env -i HOME="$t" PATH="$t/bin:$PATH" FX="$t/fx" CREW_PLAN_DIR="$t/plan" CREW_CODE_DIR="$t/app" \
  GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.test GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.test \
  bash "$t/scripts/push-pr.sh" "$@" 2>&1); }
remote_has() { git -C "$t/origin/github.com/acme/app.git" rev-parse -q --verify "refs/heads/$1" >/dev/null; }

reset; (cd "$t/app" && git switch -q -c feature)
out=$(run); [ $? = 2 ] && ! remote_has feature && ok "refuses a non-claude branch" || no "non-claude branch: $out"

reset; out=$(run --label extra); code=$?
if [ $code = 0 ] && remote_has claude/x && grep -q 'PR #7 https://example.test/pull/7' <<<"$out" \
   && grep -q 'repos/acme/app/pulls.*-F draft=false' "$t/fx/log" && grep -q 'Generated with Claude Code' "$t/fx/log" \
   && grep -q 'labels.*labels\[\]=in-progress -f labels\[\]=extra' "$t/fx/log"; then ok "new branch: pushes, opens a non-draft labelled PR"
else no "new branch: exit $code, $out, log: $(cat "$t/fx/log" 2>/dev/null)"; fi

reset; echo '[{"number": 3, "state": "open", "html_url": "https://example.test/pull/3", "base": {"ref": "main"}}]' >"$t/fx/claude_x.json"
out=$(run); code=$?
[ $code = 0 ] && grep -q 'PR #3' <<<"$out" && ! grep -q '/pulls ' "$t/fx/log" 2>/dev/null && ok "open PR: pushes, opens none" || no "open PR: exit $code, $out"

reset; (cd "$t/app" && git push -q origin claude/x && g commit -q --allow-empty -m mine && git reset -q --hard HEAD~2 && g commit -q --allow-empty -m other)
out=$(run); [ $? = 4 ] && grep -q "another session" <<<"$out" && ok "remote ahead: stops with exit 4" || no "remote ahead: $out"

reset; echo '[{"number": 5, "state": "closed", "merged_at": "2026-01-01T00:00:00Z", "base": {"ref": "main"}}]' >"$t/fx/claude_x.json"
out=$(run); code=$?
if [ $code = 0 ] && remote_has claude/x-r2 && ! remote_has claude/x && grep -q 'Follows #5' "$t/fx/log" \
   && [ "$(git -C "$t/app" log -1 --format=%s claude/x-r2)" = "add a" ]; then ok "merged PR: moves commits to claude/x-r2"
else no "merged PR: exit $code, $out"; fi

reset; (cd "$t/app" && git push -q origin claude/x:claude/x && git push -q origin main:main)
echo '[{"number": 5, "state": "closed", "merged_at": "2026-01-01T00:00:00Z"}]' >"$t/fx/claude_x.json"
(cd "$t/app" && git switch -q main && git merge -q --ff-only claude/x && git push -q origin main && git switch -q claude/x)
out=$(run); [ $? = 0 ] && grep -q 'nothing to push' <<<"$out" && ! remote_has claude/x-r2 && ok "merged PR, nothing new: pushes nothing" || no "merged, nothing new: $out"

reset; (cd "$t/app" && git push -q origin HEAD:claude/dep)
echo '[{"number": 4, "state": "closed", "merged_at": "2026-01-01T00:00:00Z"}]' >"$t/fx/claude_dep.json"
out=$(run --base claude/dep); [ $? = 0 ] && grep -q 'using main' <<<"$out" && grep -q 'base=main' "$t/fx/log" && ok "merged stacked base: retargets to main" || no "stacked base: $out"

echo "push-pr.test: $pass passed, $failn failed"; [ "$failn" = 0 ]
