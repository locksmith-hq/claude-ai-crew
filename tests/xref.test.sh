#!/usr/bin/env bash
# Cross-reference test: every script, skill and prompt named in the docs, prompts and skills exists.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
pass=0; failn=0
ok() { pass=$((pass+1)); }; no() { echo "FAIL $1"; failn=$((failn+1)); }
# scripts/<name>.sh mentioned anywhere in prompts, skills, docs, README, workflows, templates
while IFS= read -r s; do
  [ -f "scripts/$s" ] && ok || no "referenced script missing: scripts/$s"
done < <(grep -rhoE 'scripts/[a-z0-9-]+\.sh' prompts .claude/skills docs README.md .github templates 2>/dev/null | sed 's#scripts/##' | sort -u)
# skills named with "the `<name>` skill" in prompts
while IFS= read -r k; do
  [ -f ".claude/skills/$k/SKILL.md" ] && ok || no "referenced skill missing: $k"
done < <(grep -rhoE '`[a-z-]+` skill' prompts .claude/skills 2>/dev/null | sed -E 's/`([a-z-]+)` skill/\1/' | grep -vE '^(openspec-.*|this|a|the)$' | sort -u)
# every skill has front matter name matching its directory
for d in .claude/skills/*/; do
  n=$(basename "$d"); grep -q "^name: $n\$" "$d/SKILL.md" && ok || no "skill $n: front matter name mismatch"
done
# every prompt starts with a header comment naming the domain-pack keys
for f in prompts/*.md; do head -3 "$f" | grep -q 'Domain-pack keys read' && ok || no "$f: missing domain-pack header"; done
echo "xref.test: $pass passed, $failn failed"; [ "$failn" = 0 ]
