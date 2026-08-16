# Agent environment router

This bundle supplies execution capability. It does not supersede the current user's instruction or the target project's own `AGENTS.md`, dependency authority, safety rules, or command surface.

Keep environment context small: do not preload `README.md`, manifests, build notes, or third-party notices unless the current task needs them.

## Route by need

- If a required local capability is uncertain, run `agent-env doctor` before concluding a tool is unavailable.
- If GitHub may be needed in this turn, run `agent-env github` **once before substantial GitHub-dependent work**.
  - If it reports `Shell GitHub network: unavailable` (exit 3), treat remote GitHub shell access as unavailable for the rest of the session unless the host/network changes. Do not retry `gh` authentication/API calls or GitHub `git fetch/push`; local Git still works. Use a platform GitHub connector/app if one is available.
  - If shell GitHub networking is reachable but no credential source exists and the user is engaged, run `agent-env github-auth`, let the user complete browser/device authorization, then rerun `agent-env github` and continue.
  - If a credential exists but GitHub rejects it, diagnose that credential/account state; do not blindly re-authenticate.
  - For an HTTPS GitHub worktree that will push, run `agent-env github-git` once in that repository. It installs only a repo-local, location-neutral `gh` credential helper and verifies the push path with a no-write dry run.
- Never print or request a GitHub token when the interactive OAuth flow is available. Never use `gh auth status --show-token`.
- Do not request broader GitHub OAuth scopes in advance. If a concrete operation requires an additional scope, request only that scope while the user is engaged, verify the operation, and resume the task.
- Credentials are host/session state. Do not copy credentials, SSH keys, `.npmrc`, cloud secrets, or production database secrets into this bundle.
- Use project-owned commands and pinned dependencies when the project provides them. The bundle gives an agent tools; it does not grant permission to bypass repository controls.
- For Magnet Photos, use the repository `Makefile` for Supabase/database operations rather than raw Supabase commands unless the user explicitly authorizes a one-off command.
- Treat the verified payload as immutable. Ad-hoc UV tools, UV-managed extra Pythons, npm globals, and caches belong under `state/`; populated state is per-location/disposable and may need recreation after moving the bundle.

Use `agent-env help` for the small command surface. Read `README.md` only when environment operation, recovery, portability, or build details are relevant.
