# Agent routing

This bundle supplies portable execution capability. It never supersedes the user or the target repository.

1. Follow current user instructions and the target repository's own `AGENTS.md`/documented commands first.
2. Prefer an available native/platform capability when it fully covers the operation, then repository-owned commands/dependencies, then this toolbox to fill a demonstrated execution gap.
3. Use `agent-env doctor` or `agent-env capabilities` when local capability is uncertain; do not preload the full README just to discover tools.
4. PostgreSQL is explicit capability, not ambient PATH. Use repository-owned database commands when defined; otherwise `agent-env postgres run ...` creates an isolated disposable local server and `agent-env pg TOOL ...` invokes a client utility.
5. Offline Node capsules never create project dependencies. `agent-env node-deps hydrate` acts only when the repository lock exactly matches a bundled package/version/integrity.
6. If shell GitHub is genuinely needed, run `agent-env github` once; use `agent-env github-git` only when the current HTTPS worktree actually needs Git credential wiring. Do not repeatedly retry known-blocked shell networking; use an available platform connector instead.
7. Credentials remain host/session state. The verified payload is immutable; caches, ad-hoc tools, disposable databases, and other mutable data belong under `state/`.
8. Preserve one logical long-running repository validation. Give it an adequate outer timeout, or keep/supervise and poll that same process. Do not fragment a suite merely to satisfy an agent wrapper timeout.
9. Use `agent-env help` for commands and the runtime README only for deeper environment/recovery detail.
