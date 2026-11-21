# GitHub Apps and agent identity

Give each agent role its own GitHub App, so every action is attributable to a role and routing can trust the login instead of the text.

## Why one App per role
- **Attribution:** with one shared human account, GitHub cannot tell a worker's comment from the lead's, and the human gets no notification for their own account's activity.
- **Routing:** debate turn caps, "who may open this channel" and "who is woken" are enforced from the author login. That only means something if roles cannot post as each other.
- **Least privilege:** each App is installed only on the repos the role needs, with only the permissions it needs (for example the PM: issues and PRs write, code read; research: issues write, contents read).
- **Trust of the review status:** the independent review's verdict is trusted only because it comes from a fixed identity. If agents act as the owner, they could forge it. Keep the review in GitHub Actions, not in a routine.
- Webhooks off. Private Apps owned by the org.

## How a run acts as its App
Observed 2026-11 design that worked:
1. One cloud environment per role, holding only that role's App private key (base64) as an environment variable (for example `AGENT_APP_KEY_<PERSONA>`). A run can read every key in its environment, so roles that must not impersonate each other never share an environment. Workers of the same role may share one.
2. A start script signs a fresh App JWT from the key and swaps it for a one-hour installation token. It sets the git author, points pushes at github.com with the token, and puts a `gh` shim on PATH.
3. If no token comes back, the script prints `FAIL identity` and exits, and the run stops. It never falls back to the owner account.
4. An environment with no App keys at all still runs as the owner (with a warning) until keys are set; an environment with other keys but none for this persona fails.
5. Workers sharing an environment pass their persona to the start script from their prompt.

Why not a network secret: a network secret is a fixed header, but the token request needs a JWT signed with the App key, and GitHub caps that JWT at 10 minutes (observed 2026-11, the cause of a multi-day pause).

## Owner-accepted tradeoffs
- **App keys live in the VM environment** (readable by the model), an exception to "no secrets in the VM". The run sees only the one-hour installation token in practice, and that token reaches only the installed repo. Revoke a key in the App settings.
- **Proxy bypass (observed 2026-11):** the session proxy refused GitHub App token requests (`/app/installations/.../access_tokens`) with 403. The owner chose to send App traffic (token request, `gh` with the App token, git to github.com) straight to GitHub, skipping that proxy. The App's installation scope is then the limit. Revisit when the vendor supports App identities in routines. Verified in real runs; recorded as a known limitation, not a fix.
- **A key per environment** means more environments to maintain.

## Identity smoke test
Before switching real routines: create a test App, a copy of the dev environment with the test key, and a routine with no schedule whose prompt is "run the identity smoke script and report". The script sets up identity, pushes an empty commit, opens and closes a PR, comments and labels, and checks each is authored by the test App. Delete the test key afterwards.

## Alerting the human
GitHub never notifies someone about their own activity, and App-authored mentions need care. Pattern: the agent that raises a `needs-owner` issue writes the `@owner` mention itself (the App is a different user, so GitHub notifies); for issues a human account opened, a small workflow edits the body to start with an owner mention. Also check that "mentions to email" is on in the owner's notification settings.

## Sources of truth
Your App table (role, App, permissions, environment) and the start script.
