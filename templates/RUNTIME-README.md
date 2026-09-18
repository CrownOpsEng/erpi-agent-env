# ERPI Agent Environment @PRODUCT_VERSION@

Source: `@SOURCE_DESCRIPTION@`

Source commit: `@SOURCE_COMMIT@`

Portable Linux x86-64 execution capability for AI-agent work. The target repository remains authoritative for dependencies, schemas, commands, safety rules, and application architecture.

## Start

```bash
source /path/to/erpi-agent-env/activate
agent-env doctor
agent-env capabilities
```

Do not preload this README merely to discover tools; `agent-env help`, `doctor`, and `capabilities` are the cheap routing surfaces.

## Database capability

PostgreSQL is intentionally not added to ordinary PATH.

```bash
agent-env postgres run -- make check-pg
agent-env postgres run --port 54322 -- bash
agent-env postgres run --bootstrap-user agent_bootstrap -- bash
agent-env pg psql -Atc 'select version()'
agent-env pg pg_dump -Fc mydb -f dump.pg
agent-env pgtap tests/database/*.test.sql
```

`postgres run` creates a new UTF-8, checksummed, loopback-only disposable PostgreSQL 17.10 cluster under `state/postgres/`, scrubs inherited remote database targeting, uses local-only trust authentication, executes one command, shuts the cluster down, verifies page checksums, and deletes it unless `--keep` is explicitly requested. If the outer process starts as root, the database server is executed as `nobody`; the requested command remains under the invoking identity.

By default the bootstrap superuser is named `postgres`. Use `--bootstrap-user NAME` when privilege emulation requires a different bootstrap identity—for example so the role named `postgres` can instead be created as a non-superuser migration principal. The selected bootstrap identity is also exported to the child command as `PGUSER` and in `DATABASE_URL`; all other isolation, cleanup, and loopback-only behavior is unchanged.

Provider-specific role/configuration state remains target-repository bootstrap data, not environment policy. PostgreSQL accepts unknown two-part configuration names as custom placeholders, but those placeholders are superuser-settable by default; when a managed platform grants a non-superuser migration principal permission to persist one, model that explicitly from the alternate bootstrap superuser with `GRANT SET ON PARAMETER "provider.setting" TO migration_role` before replaying migrations. A `permission denied to set parameter` error therefore calls for checking the target platform's parameter ACLs rather than assuming plain PostgreSQL cannot represent the setting.

Unix-domain sockets are deliberately disabled for this disposable runtime. All bundled database clients target `127.0.0.1`, so disabling unused sockets keeps database startup independent of the relocated bundle pathname and avoids Linux Unix-socket pathname limits under deep hostile relocation.

The runtime includes pgTAP 1.3.3, plpgsql_check 2.8.11, pgbench, pg_dump/pg_restore, pg_amcheck, pg_checksums and normal client helpers. Project-specific compatibility roles, migrations, fixture data, test expectations, and production credentials do not belong in this bundle.


### Supabase CLI

`supabase` runs the pinned official Supabase CLI 2.117.0 Linux amd64 distribution. The wrapper always binds the matching bundled `supabase-go` companion while leaving `HOME`, XDG paths, access tokens, project credentials, and network policy as host/session state. Filesystem-only commands such as `supabase init` and `supabase migration new` work without a container runtime; commands that manage the local Supabase stack still require a usable host Docker-compatible runtime and any remote operations still require host network access and credentials.

### PostgREST request execution

`agent-env postgrest run --db-uri postgresql://authenticator@127.0.0.1:54322/postgres --db-schemas api --db-anon-role anon --port 3000 -- COMMAND` starts the pinned standalone PostgREST 16.2 process, waits for its schema cache to become ready, exports `POSTGREST_URL` to `COMMAND`, and tears the service down when that command exits. The version is the exact upstream native default selected by the qualified Supabase CLI 2.117.0 baseline.

Database URLs are restricted to numeric loopback and query parameters capable of retargeting libpq are refused. HTTP is always bound to `127.0.0.1`; inherited `PGRST_*` variables are scrubbed before the service starts. Optional `--db-extra-search-path` and `--db-pre-request` values are repository-owned PostgREST configuration, not provider policy. This surface is for real PostgREST request-role, transaction, search-path, pre-request and RPC semantics. It deliberately does not emulate Kong, Supabase Auth/API-key routing, Storage, or managed-platform behavior.

### pg-delta planning

`agent-env pg-delta plan --source postgresql://... --target postgresql://... --out DIR` generates numbered SQL plan files plus `envelope.json`. Both live URLs must use numeric loopback (`127.0.0.1` or `::1`); inherited PostgreSQL targeting variables are scrubbed, and remote URLs are refused before connection. The output directory must be new or empty.

This is deliberately **plan-only**. The upstream pg-delta `apply` and `sync` commands are not exposed. Version 1.0.0-alpha.49 plus its matched `@supabase/pg-topo` 1.0.0-alpha.6 companion are pinned because they are the exact engine pair used by the qualified Supabase CLI 2.117.0 baseline; the wrapper also declares the `pg` 8.23.0 client it imports directly. Planning fails closed on pg-delta errors and strict coverage gaps instead of emitting a knowingly incomplete migration, while non-blocking diagnostics are written to stderr. Useful, safe planning compatibility is the contract, not byte-for-byte parity with every Supabase CLI wrapper option. The emitted `transactionMode` metadata remains relevant to whatever repository-owned tooling reviews or applies a plan.

## Offline repository-owned Node dependencies

The immutable capsule store currently contains exact bytes for `yaml` 2.9.0, postgres 3.4.7, `@postgres-language-server/wasm` 0.25.7, fast-check 4.9.0, pure-rand 8.4.2 and `commander` 15.0.0.

```bash
agent-env node-deps status
agent-env node-deps hydrate
agent-env node-deps clean
```

Hydration occurs only when `package-lock.json` contains the exact matching package version and npm integrity value. The command validates every destination before writing, refuses symlinked `node_modules`/scope paths or repository escapes, stages all missing packages before committing any of them, runs no lifecycle scripts, and never edits `package.json` or `package-lock.json`. A matching package already owned by the repository remains repository-owned rather than being claimed by agent-env.

Packages hydrated by agent-env are recorded with content-bound ownership metadata. `clean` first verifies every recorded package against that metadata and refuses the whole cleanup if any package was replaced or modified. Legacy/name-only ownership markers are not trusted. The target repository remains dependency authority.

## Long-running validation

A foreground wrapper timeout is not a test result. Keep one logical repository validation intact: use an adequate outer timeout; otherwise keep a persistent session and poll it; if sessions are unavailable, supervise one child process and poll that same PID/output until its true exit status is known. Split only repository-defined independent phases or deliberate failure-isolation work.

## GitHub

Credentials are host/session state and are never bundled.

```bash
agent-env github
agent-env github-auth
agent-env github-git
agent-env git-handoff restore /mnt/data/repository-handoff.zip ./repository
```

Probe shell GitHub only when it is actually needed. If shell networking is known blocked, do not retry it repeatedly; use an available platform connector/app.

`git-handoff restore` is the local side of a connector-backed repository transfer. It accepts a ZIP containing exactly `repository.bundle`, `SOURCE_SHA`, `SOURCE_BRANCH`, and `REPOSITORY`; requires a self-contained Git bundle; verifies the declared branch tip and complete history in an empty repository; ignores inherited/global/system Git configuration; reconstructs branch, tags, remote-tracking refs, canonical `https://github.com/owner/repo.git` origin and upstream without contacting GitHub; and refuses an existing destination or unsafe/malformed artifact without leaving a partial worktree. The producing repository/CI remains responsible for creating the bundle from the exact intended source ref. The environment never receives or reuses connector credentials.

## Provenance and licenses

`manifest/environment.json` records the product version, Git source ancestry, exact source commit, and runtime/tool provenance. `manifest/versions.env` and the machine-readable `manifest/sources.tsv` record lifecycle/tool pins and source artifacts, including the managed python-build-standalone build selected by pinned uv. Direct third-party license/notice material is under `licenses/third-party/`; ShellCheck's GPL license and exact corresponding source are under `licenses/shellcheck/` and `licenses/source/`. Node and CPython also retain their upstream license files inside their bundled runtime trees.

## Mutable state

Caches, ad-hoc uv/npm installs, Python bytecode, ownership markers for hydrated Node packages, and disposable PostgreSQL clusters live under `state/` or the target repository's ignored `node_modules/`. The verified payload is otherwise immutable except relocation repair of `env/pyvenv.cfg`.
