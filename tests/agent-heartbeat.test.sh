#!/usr/bin/env bash
# Offline test for agent-heartbeat.sh: the run-start post, the edits and stop, with a gh stub and a throwaway plan repo.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; S="$(cd "$HERE/../scripts" && pwd)"; pass=0; failn=0
ok() { echo "ok   $1"; pass=$((pass+1)); }; no() { echo "FAIL $1"; failn=$((failn+1)); }
W=$(mktemp -d); trap 'kill "$(cat "$W/id/heartbeat.pid" 2>/dev/null)" 2>/dev/null; rm -rf "$W"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com

git init -q --bare -b main "$W/plan.git"; git clone -q "$W/plan.git" "$W/plan" 2>/dev/null; git -C "$W/plan" checkout -q -b main 2>/dev/null
git -C "$W/plan" remote set-url origin https://github.com/acme/plan.git
jq '.repos.plan="acme/plan" | .repos.code=["acme/plan"] | .owner.login="boss" | .issues.agent_log=7' "$HERE/../examples/domain-pack/crew.json" > "$W/plan/crew.json"
git -C "$W/plan" add -A; git -C "$W/plan" commit -qm init

# gh stub: POST (comment create, `-q .html_url`) prints a comment URL; every call is logged
mkdir -p "$W/bin" "$W/id"
cat > "$W/bin/gh" <<'SH'
#!/bin/sh
echo "$*" >> "$GHLOG"
case "$*" in *"-X PATCH"*) ;; *"issues/7/comments"*) echo "https://github.com/acme/plan/issues/7#issuecomment-4242" ;; esac
SH
chmod +x "$W/bin/gh"
E() { env -i HOME="$W" PATH="$W/bin:$PATH" CREW_PLAN_DIR="$W/plan" CREW_CODE_DIR="$W/plan" AGENT_ID_DIR="$W/id" GHLOG="$W/gh.log" CREW_HEARTBEAT_SECONDS=1 "$@"; }

E env AGENT_PERSONA=lead bash "$S/agent-heartbeat.sh" start >/dev/null 2>&1
[ ! -f "$W/gh.log" ] && ok "a non-worker role posts nothing" || no "non-worker posted"

out=$(E env AGENT_PERSONA=worker-a bash "$S/agent-heartbeat.sh" start 2>&1)
grep -q 'comment 4242' <<<"$out" && ok "worker posts a run-start comment and keeps its id" || no "start: $out"
grep -q '^<!-- run-start -->' <<<"$(grep -o 'body=.*' "$W/gh.log" | head -1)" || grep -q 'run-start' "$W/gh.log" && ok "the comment carries the run-start marker" || no "marker"
sleep 3
n=$(grep -c -- '-X PATCH repos/acme/plan/issues/comments/4242' "$W/gh.log")
[ "$n" -ge 1 ] && ok "the loop edits the same comment ($n beats)" || no "no beat (log: $(cat "$W/gh.log"))"
E bash "$S/agent-heartbeat.sh" stop; sleep 0.3; m=$(grep -c -- '-X PATCH' "$W/gh.log"); sleep 2.5
[ "$(grep -c -- '-X PATCH' "$W/gh.log")" = "$m" ] && ok "stop ends the loop" || no "beats continued after stop"

echo "agent-heartbeat.test: $pass passed, $failn failed"; [ "$failn" = 0 ]
