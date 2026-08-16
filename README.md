# Magnet Agent Environment Builder v1

Builds a **portable Linux x86-64 agent execution environment** intended to be uploaded/mounted beside Magnet Photos and used by ChatGPT/Codex-style shell agents.

It is deliberately **not part of the Magnet Photos application or dependency model**. Magnet's repository remains authoritative for its own Supabase CLI, Postgres language tooling, checks, schemas, migrations, and future application stack.

The design target is high-leverage asymmetry: solve recurring agent-environment limitations once, while keeping the permanent control surface small.

## Design

The runtime has a short root `AGENTS.md` router. Agents do not need to load the build history or this manual for ordinary project work. Detailed operation remains discoverable through `agent-env help`, `README.md`, and `manifest/` only when needed.

The J2911 portable venv was used as a reference. Its strongest idea—self-repairing venv metadata around a bundled CPython runtime—is preserved. Its main portability weakness is not: a stale absolute path was found in an installed console script after relocation. This builder therefore treats **old build-root residue as a hard failure** and combines the repair pattern with `uv venv --relocatable`.

## Payload

The finished bundle pins and verifies:

- `uv` 0.12.5
- uv-managed CPython 3.13.14
- Node.js 24.19.0 LTS + npm/npx
- GitHub CLI 2.97.0
- jq 1.8.2
- yq 4.53.3
- ripgrep 15.2.0
- actionlint 1.7.12
- gitleaks 8.30.1
- a small locked Python analysis layer: httpx, jsonschema, packaging, PyYAML, tomlkit, pytest, pip, setuptools and wheel

It intentionally does **not** bundle Supabase, the Postgres language server, Git, Make, Docker/Podman, or PostgreSQL client tooling. Supabase/PGLS are repo-owned; Git/Make are basic host prerequisites; a Docker client without a usable daemon is false capability; direct database tooling would bypass the repository's deliberately safe Make surface.

## GitHub auth model

GitHub authentication is demand-driven rather than part of every environment check:

```bash
agent-env github
agent-env github-auth   # only when no usable credential exists
```

The short runtime `AGENTS.md` requires agents to validate GitHub access early when a task will need it and to complete the interactive OAuth sequence while the user is engaged. Credentials remain host/session state and are never packaged into the portable artifact.

## Build

Prerequisites: Linux x86-64 with glibc, Bash, curl, tar, xz, sha256sum, find, sed/awk/grep and internet access. WSL2 x86-64 is suitable. No sudo is used. The finished runtime assumes ordinary Linux base utilities such as `find`, `sha256sum`, `cmp`, and `diff`; these are diagnosed rather than duplicated.

```bash
./tests/static-check.sh
./build.sh
```

By default the finished artifact is written under `dist/` as:

```text
magnet-agent-env-linux-x64-v1.0.0.tar.gz
magnet-agent-env-linux-x64-v1.0.0.tar.gz.sha256
```

Use `./build.sh --help` for output/cache options. Downloads are cached separately from the finished environment so a failed build can be resumed without trusting partial payload files.

## Acceptance

The builder does not report success unless it:

1. verifies downloaded native artifacts;
2. creates the environment under a path containing spaces;
3. builds the Python venv with native uv relocation support;
4. creates an offline hashed Python recovery set;
5. rejects absolute symlinks and old build-root residue;
6. relocates to a deep path containing spaces and Unicode and self-tests;
7. destroys/rebuilds the Python venv offline and self-tests again;
8. emits and verifies immutable-file and symlink manifests;
9. archives, freshly extracts, self-tests and verifies the final artifact.

See `VALIDATION.md` for what was and was not executable in the ChatGPT construction sandbox.

## Security boundary

This increases the commands an agent can execute **inside permissions the sandbox already grants**. It cannot create network access, a Docker daemon, credentials, kernel capabilities, or filesystem permissions that the host denies.

Ad-hoc UV Python installs, UV tools, npm globals and caches are redirected to `state/` so they do not mutate the verified bundled runtimes. Do not place credentials or production secrets inside the bundle.
