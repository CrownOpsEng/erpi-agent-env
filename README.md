# Magnet Agent Environment Builder v1

Builds a **portable Linux x86-64 agent execution environment** intended to be uploaded/mounted beside Magnet Photos and used by ChatGPT/Codex-style shell agents.

It is deliberately **not part of the Magnet Photos application or dependency model**. Magnet's repository remains authoritative for its own Supabase CLI, Postgres language tooling, checks, schemas, migrations, and future application stack.

## Why this exists

AI execution sandboxes are inconsistent. A session may have Python but lack `gh`, have the wrong Node major, lack YAML/JSON/search tooling, or have no convenient way to perform broad GitHub API inspection. This bundle supplies a known capability surface without requiring root access or first-use downloads.

See `VALIDATION.md` for the exact distinction between tests completed in the construction sandbox and acceptance tests executed by a fully hydrated build.

The J2911 portable venv was used as a reference. Its strongest idea—self-repairing venv metadata around a bundled CPython runtime—is preserved. Its main portability weakness is not: a stale absolute path was found in an installed console script after relocation. This builder therefore treats **old build-root residue as a hard failure** and combines the repair pattern with `uv venv --relocatable`.

## Payload

The finished bundle pins and verifies:

- `uv` 0.12.5
- uv-managed CPython 3.13.15
- Node.js 24.19.0 LTS + npm/npx
- GitHub CLI 2.97.0
- jq 1.8.2
- yq 4.53.3
- ripgrep 15.2.0
- actionlint 1.7.12
- gitleaks 8.30.1
- a small locked Python analysis layer: httpx, jsonschema, packaging, PyYAML, tomlkit, pytest, pip, setuptools, wheel (all exact-pinned and hash-locked)

It intentionally does **not** bundle Supabase, the Postgres language server, Git, Make, Docker/Podman, or PostgreSQL client tooling. Supabase/PGLS are repo-owned; Git/Make are basic host prerequisites; a Docker client without a usable daemon is false capability; direct database tooling would bypass the repository's deliberately safe Make surface.

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

## Use

Extract with a tar implementation that preserves executable bits and symlinks:

```bash
tar -xzf magnet-agent-env-linux-x64-v1.0.0.tar.gz
source magnet-agent-env/activate
agent-env doctor
agent-env selftest
```

Activation is optional. You can instead run:

```bash
/path/to/magnet-agent-env/bin/agent-env exec gh auth status
/path/to/magnet-agent-env/bin/agent-env doctor --json
```

GitHub credentials are **not bundled**. `gh` uses the host/session authentication (`GH_TOKEN`, `GITHUB_TOKEN`, or the normal host GitHub CLI config). The environment never copies GitHub credentials into its portable state.

## Portability contract

The bundle is portable **between compatible Linux x86-64 glibc environments**, not between operating systems or CPU architectures. The build intentionally:

1. creates the environment under a path containing spaces;
2. uses native `uv --relocatable` console-script generation;
3. wraps the venv Python so `pyvenv.cfg` self-repairs to the current bundled CPython location;
4. stores Node and all native tools using root-relative wrappers/links;
5. rejects absolute symlinks;
6. rejects any remaining reference to the original build root;
7. moves the completed tree to a second, differently named path and runs the complete self-test there;
8. builds a wheelhouse so the Python layer can be reconstructed without PyPI access;
9. emits a SHA-256 manifest for all immutable files.

`state/` and `env/pyvenv.cfg` are mutable and excluded from the immutable manifest. Everything else is expected to verify byte-for-byte.

## Security boundary

This increases the commands an agent can execute **inside permissions the sandbox already grants**. It cannot create network access, a Docker daemon, credentials, kernel capabilities, or filesystem permissions that the host denies.

Do not place tokens, SSH keys, `.npmrc` credentials, GitHub CLI auth files, cloud credentials, or production database credentials inside this bundle.

## Magnet Photos usage

From a Magnet checkout:

```bash
source /path/to/magnet-agent-env/activate
agent-env doctor
make doctor
make bootstrap
make check-fast
```

`make bootstrap` uses the bundle's correct Node 24 runtime but installs the **repository-pinned** Supabase and SQL tooling from Magnet's `package-lock.json`. Continue to use the repo's Make targets rather than raw Supabase commands.

Full database validation still requires a host-provided Docker/Podman-compatible runtime.
