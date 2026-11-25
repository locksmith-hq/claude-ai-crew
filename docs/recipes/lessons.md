# Lessons

Project-independent lessons from running scheduled Claude Code agents in cloud sessions and GitHub. All were observed in real use; dates are the month first seen. Verified means reproduced in actual runs unless stated.

1. **Run a preflight before work.** Lesson: check the container daemon, toolchain, registries, dependencies and disk in one script at run start, and record any loss over about 2 minutes as friction. What happened: agents lost time not noticing the daemon was down, running long commands in the foreground and waiting without polling. Observed 2026-11.

2. **Run long commands in the background with a timeout and poll them.** Lesson: anything over about 2 minutes goes to a background runner; wait on state, not time. What happened: runs blocked on cold builds and installs; foreground sleep is blocked in cloud runs. Observed 2026-11.

3. **Rerun a failing test once.** Lesson: if a test run fails, rerun once before treating it as real and record both results. What happened: a CI-equivalent run failed four times after commits in one session; reruns passed and it was not reproducible. Observed 2026-11.

4. **Do not trust a registry just because the docs allow it.** Lesson: use Docker Hub images in cloud runs. What happened: the container registry `ghcr.io` was on the documented allowlist but returned 403. Observed 2026-11.

5. **Start the container daemon yourself, in the background.** Lesson: `dockerd &` from a SessionStart hook or preflight, not the service command. What happened: `service docker start` failed in the VM while `dockerd &` worked. Observed 2026-11.

6. **Treat root-only differences as environmental.** Lesson: tests that depend on non-root behaviour should skip when uid is 0 and let a non-root CI runner cover them. What happened: the cloud VM runs as root, which bypasses process-memory protections, so a "cannot read another process" test failed. Observed 2026-11.

7. **Install dependencies before running tests.** Lesson: run the install (`npm ci` or equivalent) in the background in preflight when `node_modules` is missing. What happened: a web test job failed because nothing had installed packages. Observed 2026-11.

8. **Always bound `docker run -i`.** Lesson: check the image's help for its transport flag, wrap it in `timeout -s KILL <s> docker run -i --rm --init --name <n>`, then `docker rm -f <n>`. What happened: an MCP server image defaulted to SSE, the stdio smoke test hung, and TERM did not stop the docker client; 300 s lost. Observed 2026-11.

9. **Merge the default branch into a stale change branch before the baseline check.** Lesson: when a branch is behind, `git merge --no-edit origin/main` (never rebase a pushed branch). What happened: a branch was cut before a fix landed, so the baseline failed on a problem already fixed on main. Observed 2026-11.

10. **Never hand-assemble run metadata.** Lesson: a script builds the block; the agent passes only its own fields. What happened: one comment nested a code fence inside another and another had no metadata, so the optimizer could not find run duration or session. Observed 2026-11.

11. **Do not pre-pull images in the setup script.** Lesson: setup has a time budget of about 5 minutes; pull on demand. What happened: a pre-pull blew the cache budget and hung a lead run. Observed 2026-11.

12. **A network secret cannot sign tokens.** Lesson: for GitHub App identity, put the App key in the environment and mint a short-lived installation token per run. What happened: a fixed-header network secret could not carry a JWT signed with the App key, and the JWT lasts at most 10 minutes, which paused the identity rollout. Observed 2026-11.

13. **Expect the session proxy to refuse App token requests.** Lesson: test identity early in a smoke routine; decide the bypass explicitly with the owner. What happened: token requests got 403 from the proxy; traffic was sent directly to GitHub with the owner's recorded acceptance. Observed 2026-11.

14. **GraphQL is blocked in cloud sessions.** Lesson: write skills with REST (`gh api repos/...`), not `gh pr` or `gh issue`. What happened: those commands were rejected by the proxy. Observed 2026-11.

15. **Job logs are blocked; annotations are not.** Lesson: read check-run annotations when CI is red. What happened: agents could not read job logs through the proxy. Observed 2026-11.

16. **Give each role only its own key.** Lesson: one environment per role (workers of one role may share). What happened: a run can read every key in its environment, so shared keys would let a worker post as the lead and make login-based routing meaningless. Observed 2026-11.

17. **Separate the open-web role.** Lesson: research runs in its own environment with its own low-privilege App and comment-only output. What happened: it avoids a prompt-injected page reaching a session that runs code. Observed 2026-11.

18. **Prefer native auto-merge over a custom merge gate.** Lesson: required checks plus an independent review status plus merge commits. What happened: a custom gate script, queue and label were replaced by plain auto-merge and deleted, removing a class of bugs. Observed 2026-11.

19. **The review status must come from a fixed identity and be required.** Lesson: set it only in a workflow, so a PR whose job never ran cannot merge. What happened: a skipped job counts as passing, a missing status does not; agents that act as the owner could otherwise forge a routine's verdict. Observed 2026-11.

20. **Reuse a PASS while the diff's patch-id is unchanged.** Lesson: do not re-review after merging main in. What happened: it saves a review run per no-op push. Observed 2026-11.

21. **Keep routine prompts as stubs.** Lesson: the prompt says "read these files from the default branch and follow them"; instruction changes go through PRs. What happened: prompts live outside git review and drift. Observed 2026-11.

22. **Agents rewrite task lists unless a guard stops them.** Lesson: allow only ticking; fail any agent branch that edits task text or agent-system files. What happened: models edit Markdown task lists; the guard enforces ticks only. Observed 2026-11 (the risk is also described in Anthropic's long-running agent harness article).

23. **Put owner gates last.** Lesson: a change parks on an owner question only when its next task is a gate task; order gated tasks after everything else. What happened: whole changes sat blocked on a question needed only by later tasks. Observed 2026-11.

24. **Never idle at an owner gate without a request open.** Lesson: when approval is needed, open a short-summary push and a `needs-owner` issue with an `Action:` line, then keep discussing until settled. What happened: silent waits. Observed 2026-11.

25. **Keep workers fed: backlog depth is the lead's job.** Lesson: keep three takeable changes, and start dependent work early against a contract task group (schema, shared types, mocks). What happened: workers ended idle while the plan had startable rows. Observed 2026-11.

26. **One tracking issue per change.** Lesson: retire per-task issues; the checklist is the task view. What happened: per-task issues added noise. Observed 2026-11.

27. **Pin agent-system changes to a weekly release.** Lesson: findings go on a backlog issue on weekdays; one release PR applies them; only hotfixes (red main, security, every run failing) go outside. What happened: constant rule changes destabilized runs. Observed 2026-11.

28. **Check a PR is still open before pushing.** Lesson: a PR can be merged mid-session; if so, branch fresh from main and cherry-pick the unmerged commits. What happened: pushes to a merged PR's branch go nowhere useful. Observed 2026-11.

29. **Hosted CI minutes can force you to disable checks.** Lesson: decide the repo visibility and CI budget up front; a gate that skips disabled checks is weak. What happened: private-repo minute limits led to CI and review being turned off for a time; a public repo restored free runners. Observed 2026-11.

30. **Test every cloud-only assumption on the first run.** Lesson: mark undocumented behaviours as "to test" and verify them in a first manual run (notifications, network allowlist on web tools, daemon start). What happened: several documented behaviours differed from reality (registry 403, proxy, usage tool). Observed 2026-11.

31. **A reusable workflow can only use the permissions its caller grants.** Lesson: give every caller job at least the permissions the called workflow requests, and test it. What happened: the first real run ended in `startup_failure` ("requesting `contents: write`... but is only allowed `contents: read`"). A test now compares each caller's grants with its reusable workflow's requests. Observed 2026-11; verified.

32. **`claude-code-action` needs a real git repository at the workspace root.** Lesson: when you check several repos into subfolders, make the root a repo with an `origin` remote and a HEAD (`git init`, `git remote add origin`, an empty commit). What happened: `fatal: not in a git directory`, then `No such remote 'origin'`. Observed 2026-11; verified.

33. **Never parse a full-screen terminal UI by joining its raw output; and never store a credential you did not test.** Lesson: read such a tool through a virtual terminal that applies cursor moves and erases, never echo its output, and check the credential with a real call (`claude -p`) before storing it. What happened: `claude setup-token` repaints its screen, joining the output put the login URL inside the token, the stored token was invalid (401) and a wide terminal did not fix it. Observed 2026-11; verified.

34. **On macOS, do not rely on a Python install for HTTPS.** Lesson: make HTTPS calls through `gh` or `curl`, which use the system certificates. What happened: a python.org build failed `urllib` with `CERTIFICATE_VERIFY_FAILED` on the first real GitHub App creation. Observed 2026-11; verified.

35. **Portable shell: macOS bash 3.2 and BSD tools differ.** Lesson: write `${a[@]+"${a[@]}"}` for possibly empty arrays under `set -u`; do not rely on `cp -n` exit codes; do not assume GNU `timeout` exits with the same code as BSD `timeout` (124 versus 137 on a KILL). What happened: three of these broke on one platform and passed on the other. Observed 2026-11; verified.

36. **A private GitHub App can only be installed on its owner's account.** Lesson: create the App under the organization that owns the repos (the manifest flow has an organization URL), and install it on only the repos it needs. What happened: an App created under a personal account could not be installed on organization repos. Observed 2026-11; verified.

37. **GitHub requires a human click to create and install an App.** Lesson: there is no API for either step, so any App-based setup needs a browser; a setup that must be fully scripted should use the `gh` login token (with its wider access) and offer Apps as an opt-in. Observed 2026-11; verified.

38. **The free GitHub plan cannot enforce review on private repos.** Lesson: no branch protection, required status checks or auto-merge on private repos means an AI review can run but cannot block a merge; decide the repo visibility or plan up front. What happened: the review workflow could not be triggered on the sandbox. Observed 2026-11; verified.

39. **Pull Docker Hub images through a mirror.** Lesson: start the container daemon with `registry-mirrors: ["https://mirror.gcr.io"]` in `/etc/docker/daemon.json` (preflight does this), and never pull from Docker Hub unauthenticated at scale. Misses fall back to Docker Hub; if 429s return on images the mirror lacks, add a Docker Hub token or a pull-through cache. What happened: workers sharing a few egress IPs hit Docker Hub's anonymous limit (100 pulls per 6 hours) and image builds failed with 429. Observed 2026-11.
