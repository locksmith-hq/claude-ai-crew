# claude-ai-crew rules

## Nothing org-specific in this repo
This harness must work for any org. Never commit anything that belongs to one org or project:
- org, owner, user or repo names, project names, persona names, personal emails;
- trigger ids, secret values, account ids, URLs of a specific org's infrastructure;
- defaults that assume one org (derive from `git remote` or require a flag; put examples in `examples/` with the `acme` fixtures).

Org values live in the org's plan repo `crew.json` (overrides only), repo secrets and Actions variables.
`crew.defaults.json` and `examples/` stay generic. Tests use `acme` fixtures.
`scripts/leak-check.sh` enforces this in CI; the org's own names come from the repo Actions variable `LEAK_DENYLIST` (one regex per line), never from a committed file.
