#!/usr/bin/env bash
# Tests for scripts/run-lock.sh (and change-issue.sh) with `gh` and `sleep` replaced by stubs first on PATH.
# The stub keeps issues and comments as JSON files, so locks, claims, releases, expiry and races run offline.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; S="$HERE/../scripts"; pass=0; failn=0
ok() { echo "ok   $1"; pass=$((pass+1)); }; no() { echo "FAIL $1"; failn=$((failn+1)); }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin" "$W/plan/changes/c1" "$W/plan/changes/c2" "$W/plan/changes/c3" "$W/state"
jq '.repos.plan="acme/plan" | .repos.code=["acme/app"]' "$HERE/../examples/domain-pack/crew.json" >"$W/plan/crew.json"
printf '# Proposal: Third change\n' >"$W/plan/changes/c3/proposal.md"

printf '#!/bin/sh\nexit 0\n' >"$W/bin/sleep"
cat >"$W/bin/gh" <<'STUB'
#!/usr/bin/env bash
# Minimal gh stub: only `gh api`. State in $STUB_DIR: issues.json, comments-<n>.json. -q is applied with jq -r.
[ "$1" = api ] || exit 1; shift
method=GET; q=""; ep=""; body=""; title=""
while [ $# -gt 0 ]; do
  case "$1" in
    -q) q=$2; shift ;; -X) method=$2; shift ;; --paginate) ;;
    -f) [ "$method" = GET ] && method=POST  # like gh: fields imply POST
      case "$2" in body=*) body=${2#body=} ;; title=*) title=${2#title=} ;; esac; shift ;;
    *) ep=$1 ;;
  esac; shift
done
out() { if [ -n "$q" ]; then jq -r "$q"; else cat; fi; }
iso() { date -u -d "@$1" +%FT%TZ 2>/dev/null || date -u -r "$1" +%FT%TZ; }
now=$(date -u +%s)
add_comment() { # <issue> <body> <epoch>
  local f="$STUB_DIR/comments-$1.json"; [ -f "$f" ] || echo '[]' >"$f"
  jq --arg b "$2" --arg t "$(iso "$3")" '. + [{id: (length + 1), created_at: $t, body: $b}]' "$f" >"$f.n" && mv "$f.n" "$f"
}
case "$method $ep" in
  "GET repos/acme/plan/issues?labels=change"*) out <"$STUB_DIR/issues.json" ;;
  "GET repos/acme/plan/issues/"*/comments*) n=${ep#repos/acme/plan/issues/}; n=${n%%/*}; { cat "$STUB_DIR/comments-$n.json" 2>/dev/null || echo '[]'; } | out ;;
  "POST repos/acme/plan/issues/"*/comments)
    n=${ep#repos/acme/plan/issues/}; n=${n%%/*}
    [ -n "${STUB_RACE:-}" ] && add_comment "$n" "LOCK $STUB_RACE" $((now - 1))  # a rival whose LOCK lands just before ours
    add_comment "$n" "$body" "$now"; echo '{"id":1}' | out ;;
  "POST repos/acme/plan/issues")
    n=$(( $(jq length "$STUB_DIR/issues.json") + 10 ))
    jq --arg t "$title" --argjson n "$n" '. + [{number: $n, title: $t}]' "$STUB_DIR/issues.json" >"$STUB_DIR/i.n" && mv "$STUB_DIR/i.n" "$STUB_DIR/issues.json"
    echo "{\"number\":$n}" | out ;;
  *) echo "gh stub: unhandled $method $ep" >&2; exit 1 ;;
esac
STUB
chmod +x "$W/bin/gh" "$W/bin/sleep"

echo '[{"number":1,"title":"c1: First"},{"number":2,"title":"c2: Second"}]' >"$W/state/issues.json"
iso() { date -u -d "@$1" +%FT%TZ 2>/dev/null || date -u -r "$1" +%FT%TZ; }
reset() { rm -f "$W"/state/comments-*.json; }
# lock <holder> [env...]: run run-lock.sh with the stub on PATH and no session id in the environment
RL() { env -i HOME="$W" PATH="$W/bin:$PATH" STUB_DIR="$W/state" CREW_CONFIG="$W/plan/crew.json" CREW_PLAN_DIR="$W/plan" CREW_CODE_DIR="$W/plan" "${ENVX[@]}" bash "$S/run-lock.sh" "$@"; }
ENVX=(X=1)
bodies() { jq -r '[.[].body]|join("|")' "$W/state/comments-$1.json" 2>/dev/null; }

reset
RL acquire a c1 >/dev/null; [ "$?" = 0 ] && [ "$(bodies 1)" = "LOCK a" ] && ok "acquire on a free change" || no "acquire on a free change: $(bodies 1)"
[ "$(RL holder x c1)" = a ] && ok "holder prints the holder" || no "holder prints the holder"
out=$(RL acquire b c1); [ "$?" = 1 ] && grep -q busy <<<"$out" && ok "second holder is told busy" || no "second holder is told busy: $out"
out=$(RL acquire a c1); [ "$?" = 0 ] && grep -q 'already held' <<<"$out" && [ "$(bodies 1)" = "LOCK a" ] && ok "re-acquire by the holder is a no-op" || no "re-acquire: $out"
RL release b c1 >/dev/null; [ "$(bodies 1)" = "LOCK a" ] && ok "release by a non-holder does nothing" || no "release by non-holder: $(bodies 1)"
RL release a c1 >/dev/null; [ "$(bodies 1)" = "LOCK a|UNLOCK a" ] && [ -z "$(RL holder x c1)" ] && ok "release by the holder frees it" || no "release: $(bodies 1)"
RL acquire b c1 >/dev/null; [ "$?" = 0 ] && [ "$(RL holder x c1)" = b ] && ok "another holder acquires after release" || no "acquire after release"

# expiry: a LOCK older than the TTL does not block
reset; now=$(date -u +%s)
echo "[{\"id\":1,\"created_at\":\"$(iso $((now - 7200)))\",\"body\":\"LOCK old\"}]" >"$W/state/comments-1.json"
RL acquire a c1 >/dev/null; [ "$?" = 0 ] && [ "$(RL holder x c1)" = a ] && ok "an expired lock (2h) does not block" || no "expired lock blocks: $(bodies 1)"
reset; echo "[{\"id\":1,\"created_at\":\"$(iso $((now - 60)))\",\"body\":\"LOCK fresh\"}]" >"$W/state/comments-1.json"
RL acquire a c1 >/dev/null; [ "$?" = 1 ] && ok "a 60s-old lock blocks under the default TTL" || no "fresh lock does not block"
ENVX=(RUN_LOCK_TTL=30); RL acquire a c1 >/dev/null; [ "$?" = 0 ] && ok "RUN_LOCK_TTL=30 expires the 60s-old lock" || no "TTL override"; ENVX=(X=1)

# claim: the first free id, skipping busy ones; none free -> exit 1
reset; RL acquire other c1 >/dev/null
out=$(RL claim a c1 c2); [ "$?" = 0 ] && [ "$out" = c2 ] && [ "$(RL holder x c2)" = a ] && ok "claim skips a busy change and takes the next" || no "claim: $out"
out=$(RL claim b c1 c2); [ "$?" = 1 ] && [ -z "$out" ] && ok "claim with nothing free exits 1" || no "claim none free: $out"
out=$(RL claim a c1 c2); [ "$out" = c2 ] && ok "claim by the holder returns its own change" || no "claim own: $out"

# lost race: a rival LOCK lands before ours
reset; ENVX=(STUB_RACE=rival); out=$(RL acquire a c1); rc=$?; ENVX=(X=1); [ "$rc" = 1 ] && grep -q 'lost race to rival' <<<"$out" && ok "lost race is reported" || no "lost race: $out"

# session id: the holder gets @<session> appended, so two sessions with the same name do not share a lock
reset; ENVX=(CLAUDE_CODE_SESSION_ID=s1); RL acquire w c1 >/dev/null
[ "$(bodies 1)" = "LOCK w@s1" ] && ok "session id is appended to the holder" || no "session id: $(bodies 1)"
ENVX=(CLAUDE_CODE_SESSION_ID=s2); RL acquire w c1 >/dev/null; [ "$?" = 1 ] && ok "same name, other session: busy" || no "same name, other session"
ENVX=(X=1)

# no issue yet: holder and release are quiet no-ops, acquire creates the issue for a known id, rejects unknown ones
reset
[ -z "$(RL holder x c3)" ] && RL release a c3 >/dev/null && ok "holder/release with no issue exit 0 quietly" || no "holder/release with no issue"
RL acquire a c3 >/dev/null; [ "$?" = 0 ] && jq -e 'any(.[]; .title == "c3: Third change")' "$W/state/issues.json" >/dev/null && ok "acquire creates the change issue (title from proposal.md)" || no "issue creation"
out=$(RL acquire a nope 2>&1); [ "$?" = 1 ] && grep -q 'unknown change id' <<<"$out" && ok "unknown change id is rejected" || no "unknown id: $out"
RL acquire a >/dev/null 2>&1; [ "$?" = 2 ] && ok "missing arguments exit 2" || no "usage exit code"

echo "run-lock.test: $pass passed, $failn failed"; [ "$failn" = 0 ]
