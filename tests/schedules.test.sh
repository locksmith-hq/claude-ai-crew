#!/usr/bin/env bash
# Tests for scripts/lib/schedules.py: the generated roles and schedules follow the cadence rules.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; SCH="$HERE/../scripts/lib/schedules.py"; BASE="$HERE/../examples/domain-pack/crew.json"; pass=0; failn=0
ok() { echo "ok   $1"; pass=$((pass+1)); }; no() { echo "FAIL $1"; failn=$((failn+1)); }
S=$(mktemp -d); P="$S/crew.json"
python3 "$SCH" init-pack --project demo --owner me --plan o/plan --code o/app --code o/lib --harness o/h --workers 3 --base "$BASE" --out "$P" || no "init-pack runs"
bash "$HERE/../scripts/validate-pack.sh" "$P" >/dev/null 2>&1 && ok "a generated pack validates" || no "a generated pack validates"
[ "$(jq -r '[.roles|keys[]]|sort|join(",")' "$P")" = "lead,pm,research,worker-a,worker-b,worker-c" ] && ok "init-pack: 3 workers plus lead, pm and research" || no "init-pack roles"
[ "$(jq -r '.repos.code|join(",")' "$P")" = "o/app,o/lib" ] && ok "init-pack: several code repos" || no "init-pack code repos"
jq -e '.channels["needs-rescue"].from == ["worker-a","worker-b","worker-c"] and .default_worker == "worker-a"' "$P" >/dev/null && ok "init-pack: channels list every worker" || no "init-pack channels"
python3 "$SCH" render --crew "$P" --out "$S/out" --harness-repo o/h --harness-ref main >/dev/null
[ "$(ls "$S/out" | wc -l | tr -d ' ')" = 6 ] && ok "render: one caller per role" || no "render: one caller per role"
if grep -qE 'cron: "(0|30) ' "$S"/out/*.yml; then no "no schedule starts at :00 or :30"; else ok "no schedule starts at :00 or :30"; fi
grep -q "cron" "$S/out/crew-schedule-research.yml" && no "research has no cron" || ok "research has no cron (on demand only)"
grep -q "workflow_dispatch" "$S/out/crew-schedule-research.yml" && ok "every caller can be started by hand" || no "every caller can be started by hand"
# peak hours: no weekday worker run in 15-20 UTC
bad=0; while IFS= read -r l; do hrs=$(sed -E 's/^ *- cron: "[0-9]+ ([^ ]+) .*/\1/' <<<"$l"); days=$(sed -E 's/.* ([^ ]+)"$/\1/' <<<"$l"); [ "$days" = "1-5" ] || continue
  for r in $(tr ',' ' ' <<<"$hrs"); do lo=${r%-*}; hi=${r#*-}; for h in $(seq "$lo" "$hi"); do [ "$h" -ge 15 ] && [ "$h" -le 20 ] && bad=1; done; done
done < <(grep "cron:" "$S/out/crew-schedule-worker-a.yml")
[ "$bad" = 0 ] && ok "workers avoid the weekday peak hours" || no "workers avoid the weekday peak hours"
a=$(grep -o 'cron: "[0-9]*' "$S/out/crew-schedule-worker-a.yml" | head -1); b=$(grep -o 'cron: "[0-9]*' "$S/out/crew-schedule-worker-b.yml" | head -1)
[ "$a" != "$b" ] && ok "workers are staggered (different minutes)" || no "workers are staggered"
# overrides
jq '.schedules.roles["worker-b"].enabled=false | .schedules.roles.pm.cron=["5 7 * * 1"] | .schedules.avoid_hours_utc=[9]' "$P" > "$S/o.json"
python3 "$SCH" render --crew "$S/o.json" --out "$S/o" --harness-repo o/h --harness-ref main >/dev/null
grep -q "cron" "$S/o/crew-schedule-worker-b.yml" && no "enabled=false removes the cron" || ok "enabled=false removes the cron"
grep -q 'cron: "5 7 \* \* 1"' "$S/o/crew-schedule-pm.yml" && ok "a role's cron can be overridden" || no "a role's cron can be overridden"
grep -E 'cron: ".* 1-5"' "$S/o/crew-schedule-worker-a.yml" | grep -qE '[ ,-]9[ ,-]|,9 | 9,' && no "avoid_hours_utc is configurable" || ok "avoid_hours_utc is configurable"
# generated YAML is valid and calls the reusable workflow with the right inputs
command -v ruby >/dev/null && ruby -ryaml -e 'y=YAML.safe_load(File.read(ARGV[0]), aliases: true); j=y["jobs"]["run"]; exit(j["uses"]=="o/h/.github/workflows/role-run.yml@main" && j["with"]["role"]=="lead" && j["with"]["plan_repo"]=="o/plan" ? 0 : 1)' "$S/out/crew-schedule-lead.yml" && ok "a generated caller is valid YAML calling role-run.yml" || { command -v ruby >/dev/null && no "a generated caller is valid YAML"; }
[ "$(python3 "$SCH" roles --crew "$P" | wc -l | tr -d ' ')" = 6 ] && ok "roles lists every role" || no "roles lists every role"
rm -rf "$S"; echo "schedules.test: $pass passed, $failn failed"; [ "$failn" = 0 ]
