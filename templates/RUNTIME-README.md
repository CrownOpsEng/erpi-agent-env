# Magnet Agent Environment

A portable **Linux x86-64 glibc AI-agent execution environment** built for working on Magnet Photos and similar repositories from constrained shell sessions.

This environment is external tooling. It is **not part of the Magnet Photos application architecture**, and it does not replace repository-owned dependencies or safety policy.

## Start here

From any extraction location:

```bash
source /path/to/magnet-agent-env/activate
agent-env doctor
agent-env selftest
```

Activation is convenient but optional:

```bash
/path/to/magnet-agent-env/bin/agent-env exec gh auth status
/path/to/magnet-agent-env/bin/agent-env doctor --json
```

## What is bundled

- uv and a bundled CPython runtime
- a relocatable Python analysis environment with offline recovery wheels
- Node.js 24 LTS with npm/npx
- GitHub CLI (`gh`)
- jq and yq
- ripgrep (`rg`)
- actionlint
- gitleaks
- a small generic Python analysis layer: httpx, jsonschema, packaging, PyYAML, tomlkit, pytest, pip, setuptools and wheel

Exact versions, sources and hashes are under `manifest/`.

## Commands

```text
agent-env doctor [--json]  Diagnose the bundle, host capabilities, GitHub auth and current repository
agent-env selftest         Exercise bundled runtimes/tools and relocation invariants
agent-env verify           Verify immutable-file checksums and symlink topology
agent-env repair           Repair relocation-sensitive Python metadata
agent-env rebuild-python   Destroy/recreate the Python venv offline from bundled artifacts
agent-env versions         Print the environment manifest
agent-env exec CMD ...     Run a command with the environment active
agent-env root             Print the resolved bundle root
```

## Magnet Photos workflow

From a Magnet Photos checkout:

```bash
source /path/to/magnet-agent-env/activate
agent-env doctor
make doctor
make bootstrap
make check-fast
```

The bundle supplies the Node major required by the repository. `make bootstrap` still installs the exact **repository-pinned** Supabase CLI and Postgres language tooling from `package-lock.json`. Continue to use Magnet's Make targets rather than raw Supabase commands.

Full database checks still require a host-provided working Docker/Podman-compatible runtime.

## GitHub authentication

Credentials are deliberately not stored in the bundle. `gh` uses credentials made available by the host/session, such as `GH_TOKEN`, `GITHUB_TOKEN`, or the normal host GitHub CLI configuration.

Do not copy tokens, SSH keys, `.npmrc` credentials, cloud credentials or production database secrets into this directory.

## Portability contract

The bundle may be moved to a different pathname on a **compatible Linux x86-64 glibc host**. It is not cross-OS or cross-architecture.

The environment combines `uv venv --relocatable` with a location-aware Python wrapper because the venv still needs to identify its bundled base interpreter after relocation. Build-time tests reject absolute symlinks and stale references to the original build path, then move, self-test, destroy/rebuild the Python venv offline, archive, extract and test again.

Prefer the supplied `.tar.gz` artifact. Tar reliably preserves executable permissions and symlinks; ZIP extraction behavior varies across hosts.

## Integrity and recovery

`agent-env verify` checks the immutable payload against `manifest/SHA256SUMS` and verifies symlink topology against `manifest/SYMLINKS`.

`state/` is intentionally mutable. `env/pyvenv.cfg` is also mutable because relocation repair rewrites its absolute base-Python path.

If the Python environment is damaged:

```bash
agent-env rebuild-python
```

That rebuild is designed to work without PyPI/network access using `manifest/requirements.lock` and `wheelhouse/`.

## Boundary

This package expands the commands available **within permissions already granted by the host sandbox**. It cannot manufacture network access, credentials, a Docker daemon/socket, filesystem execution permission, kernel capabilities or unsupported CPU/OS compatibility.
