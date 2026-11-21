# Contributing

This harness is generic on purpose. A change belongs here only if it helps **any** project.

1. **No project content.** No project, company or person names, bot or persona names, trigger ids, account
   ids, hostnames or private URLs. Use the placeholders in [docs/domain-pack.md](docs/domain-pack.md).
2. **Add your own private words** (one regex per line) to the git-ignored `.leak-denylist.local`; the leak
   check blocks them locally.
3. **Run the checks** before opening a PR: `bash scripts/leak-check.test.sh`, `bash scripts/leak-check.sh`,
   `shellcheck scripts/*.sh`.
4. **Recipes and lessons** need an `Observed <YYYY-MM>` note and whether you verified them.
5. **Prompts are the product.** Keep them short, concrete and testable. A rule that can be enforced by a script
   should be a script.
