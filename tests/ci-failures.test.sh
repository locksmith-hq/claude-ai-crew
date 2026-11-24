#!/usr/bin/env bash
# Tests for scripts/ci-failures.sh and scripts/agent-comment.sh against a stubbed `gh` (fixture JSON per URL).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; pass=0; failn=0
ok() { echo "ok   $1"; pass=$((pass+1)); }; no() { echo "FAIL $1"; failn=$((failn+1)); }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
mkdir -p "$t/scripts/lib" "$t/bin" "$t/fx" "$t/plan" "$t/code" "$t/id"
cp "$HERE/../scripts/ci-failures.sh" "$HERE/../scripts/agent-comment.sh" "$HERE/../scripts/agent-identity.sh" "$t/scripts/"; cp "$HERE/../scripts/lib/crew-env.sh" "$t/scripts/lib/"
jq '.repos.plan="acme/plan" | .repos.code=["acme/app"] | .issues.agent_log=11' "$HERE/../examples/domain-pack/crew.json" >"$t/plan/crew.json"
cat >"$t/bin/gh" <<'EOF'
#!/usr/bin/env bash
# gh api <url> [-f k=v] [-q filter]: the fixture named for the url, through jq; -f writes are logged with the cwd
shift; url=$1; shift; q=.; w=""
while [ $# -gt 0 ]; do case "$1" in -q) q=$2; shift ;; -f) w="$w$2"; shift ;; esac; shift; done
[ -n "$w" ] && { printf '%s|%s|%s' "$PWD" "$url" "$w" >"$FX/last"; echo '{"html_url": "https://example.test/c/1"}' | jq -r "$q"; exit; }
case "$url" in
  */pulls/*) f=pr ;; */check-runs\?*) f=runs ;; */actions/jobs/*) f=job ;; */annotations*) f=ann ;;
  */status) f=status ;; */commits/*) f=commit ;; *) exit 1 ;;
esac
jq -r "$q" "$FX/$f.json"
EOF
chmod +x "$t/bin/gh"
run() { (cd "$t/plan" && env -i HOME="$t" PATH="$t/bin:$PATH" FX="$t/fx" CREW_PLAN_DIR="$t/plan" CREW_CODE_DIR="$t/code" \
  AGENT_ID_DIR="$t/id" "$@" 2>&1); }

echo '{"state": "closed", "merged_at": "2026-01-01T00:00:00Z"}' >"$t/fx/pr.json"
out=$(run bash "$t/scripts/ci-failures.sh" 12); [ $? = 0 ] && [ "$out" = "PR #12 is merged: nothing to fix" ] && ok "merged PR: nothing to fix" || no "merged PR: $out"

echo '{"state": "open", "head": {"sha": "abc", "ref": "claude/x"}, "base": {"ref": "main"}, "mergeable_state": "dirty"}' >"$t/fx/pr.json"
echo '{"check_runs": [
  {"id": 1, "name": "rust", "status": "completed", "conclusion": "failure", "html_url": "u1", "app": {"slug": "github-actions"}},
  {"id": 2, "name": "web", "status": "completed", "conclusion": "success", "html_url": "u2", "app": {"slug": "github-actions"}},
  {"id": 3, "name": "macos", "status": "in_progress", "conclusion": null, "html_url": "u3", "app": {"slug": "github-actions"}}]}' >"$t/fx/runs.json"
echo '{"steps": [{"name": "checkout", "conclusion": "success"}, {"name": "test-rust", "conclusion": "failure"}]}' >"$t/fx/job.json"
echo '[{"path": "crates/a/src/lib.rs", "start_line": 9, "annotation_level": "failure", "message": "a::t panicked\nmore"}]' >"$t/fx/ann.json"
echo '{"statuses": [{"context": "merge-ready", "state": "error", "description": "no review verdict"}, {"context": "x", "state": "success"}]}' >"$t/fx/status.json"
want='CONFLICT: merge origin/main into claude/x
FAIL rust (failure) u1
  step: test-rust
  crates/a/src/lib.rs:9 failure: a::t panicked
FAIL status merge-ready: no review verdict
pending: macos'
out=$(run bash "$t/scripts/ci-failures.sh" 12); code=$?
[ $code = 1 ] && [ "$out" = "$want" ] && ok "red PR: conflict, failed step, annotation, status, pending" || no "red PR: exit $code, got:"$'\n'"$out"

echo '{"sha": "abc"}' >"$t/fx/commit.json"
echo '{"check_runs": [{"id": 2, "name": "web", "status": "completed", "conclusion": "success", "html_url": "u2", "app": {"slug": "x"}}]}' >"$t/fx/runs.json"
echo '{"statuses": []}' >"$t/fx/status.json"
out=$(run bash "$t/scripts/ci-failures.sh" main); [ $? = 0 ] && [ "$out" = green ] && ok "green branch" || no "green branch: $out"

# agent-comment.sh
out=$(echo "hello" | run env AGENT_PERSONA=worker-a bash "$t/scripts/agent-comment.sh" code 5); code=$?
line=$(cat "$t/fx/last")
[ $code = 0 ] && [ "$out" = https://example.test/c/1 ] && [ "${line%%|*}" = "$t/code" ] \
  && [ "${line#*|}" = "repos/acme/app/issues/5/comments|body=<!-- agent -->
<!-- role: worker-a -->
hello" ] && ok "comment: markers added, posted from the code checkout" || no "comment: exit $code, $out, log: $line"
out=$(printf '<!-- agent -->\n<!-- role: lead -->\nx' | run bash "$t/scripts/agent-comment.sh" log)
[ "$(cut -d'|' -f2- "$t/fx/last")" = "repos/acme/plan/issues/11/comments|body=<!-- agent -->
<!-- role: lead -->
x" ] && ok "comment: log goes to issues.agent_log, markers not doubled" || no "comment log: $(cat "$t/fx/last")"
out=$(echo "  " | run bash "$t/scripts/agent-comment.sh" plan 3); [ $? = 2 ] && ok "comment: empty body refused" || no "empty body: $out"

echo "ci-failures.test: $pass passed, $failn failed"; [ "$failn" = 0 ]
