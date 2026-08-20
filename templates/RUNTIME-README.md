# Magnet Agent Environment @BUNDLE_VERSION@

Portable Linux x86-64 execution capability for AI-agent work. The target repository remains authoritative for dependencies, schemas, commands, safety rules, and application architecture.

## Start

```bash
source /path/to/magnet-agent-env/activate
agent-env doctor
agent-env capabilities
```

Do not preload this README merely to discover tools; `agent-env help`, `doctor`, and `capabilities` are the cheap routing surfaces.

## Database capability

PostgreSQL is intentionally not added to ordinary PATH.

```bash
agent-env postgres run -- make check-pg
agent-env postgres run --port 54322 -- bash
agent-env pg psql -Atc 'select version()'
agent-env pg pg_dump -Fc mydb -f dump.pg
agent-env pgtap tests/database/*.test.sql
```

`postgres run` creates a new UTF-8, checksummed, loopback-only disposable PostgreSQL 17.10 cluster under `state/postgres/`, scrubs inherited remote database targeting, uses local-only trust authentication, executes one command, shuts the cluster down, verifies page checksums, and deletes it unless `--keep` is explicitly requested. If the outer process starts as root, the database server is executed as `nobody`; the requested command remains under the invoking identity.

Unix-domain sockets are deliberately disabled for this disposable runtime. All bundled database clients target `127.0.0.1`, so disabling unused sockets keeps database startup independent of the relocated bundle pathname and avoids Linux Unix-socket pathname limits under deep hostile relocation.

The runtime includes pgTAP 1.3.3, plpgsql_check 2.8.11, pgbench, pg_dump/pg_restore, pg_amcheck, pg_checksums and normal client helpers. Project-specific compatibility roles, migrations, fixture data, test expectations, and production credentials do not belong in this bundle.

## Offline repository-owned Node dependencies

The immutable capsule store currently contains exact bytes for postgres 3.4.7, `@postgres-language-server/wasm` 0.25.7, fast-check 4.9.0 and pure-rand 8.4.2.

```bash
agent-env node-deps status
agent-env node-deps hydrate
agent-env node-deps clean
```

Hydration occurs only when `package-lock.json` contains the exact matching package version and npm integrity value. It never edits `package.json` or `package-lock.json`, runs no lifecycle scripts, and refuses to overwrite a mismatching package. The target repository remains dependency authority.

## Long-running validation

A foreground wrapper timeout is not a test result. Keep one logical repository validation intact: use an adequate outer timeout; otherwise keep a persistent session and poll it; if sessions are unavailable, supervise one child process and poll that same PID/output until its true exit status is known. Split only repository-defined independent phases or deliberate failure-isolation work.

## GitHub

Credentials are host/session state and are never bundled.

```bash
agent-env github
agent-env github-auth
agent-env github-git
```

Probe shell GitHub only when it is actually needed. If shell networking is known blocked, do not retry it repeatedly; use an available platform connector/app.

## Mutable state

Caches, ad-hoc uv/npm installs, Python bytecode, ownership markers for hydrated Node packages, and disposable PostgreSQL clusters live under `state/` or the target repository's ignored `node_modules/`. The verified payload is otherwise immutable except relocation repair of `env/pyvenv.cfg`.
