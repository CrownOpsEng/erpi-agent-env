# Magnet Agent Environment

A portable **Linux x86-64 glibc AI-agent execution environment** built for working on Magnet Photos and similar repositories from constrained shell sessions.

This environment is external tooling. It is **not part of the Magnet Photos application architecture**, and it does not replace repository-owned dependencies or safety policy.

Agents should read the root `AGENTS.md` first. It is intentionally short and routes environment use without loading this manual into every task.

## Start here

From any extraction location:

```bash
source /path/to/magnet-agent-env/activate
agent-env doctor
```

Activation is convenient but optional:

```bash
/path/to/magnet-agent-env/bin/agent-env exec gh --version
/path/to/magnet-agent-env/bin/agent-env doctor --json
```

Run `agent-env selftest` after moving/extracting the bundle, after recovery, or when environment integrity is in doubt. It is not intended as per-turn ceremony.

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
agent-env doctor [--json]  Diagnose local bundle, host commands, and current repository
agent-env github            Validate GitHub auth/API and current-repository access
agent-env github-auth       Run interactive GitHub OAuth when needed, then verify it
agent-env selftest          Exercise bundled capabilities and portability invariants
agent-env verify            Verify immutable-file checksums and symlink topology
agent-env repair            Repair relocation-sensitive Python metadata
agent-env rebuild-python    Destroy/recreate the Python venv offline from bundled artifacts
agent-env versions          Print the environment manifest
agent-env exec CMD ...      Run a command with the environment active
agent-env root              Print the resolved bundle root
```

## GitHub authentication

Credentials are deliberately **not bundled**. `gh` uses host/session authentication, including `GH_TOKEN`, `GITHUB_TOKEN`, or the normal GitHub CLI credential/config store.

For a GitHub-dependent task, validate access before substantial dependent work:

```bash
agent-env github
```

If it reports that no credential source exists, authenticate while the user is present:

```bash
agent-env github-auth
```

The command starts GitHub CLI's normal browser/device OAuth flow, then verifies the API and the current repository when one is detected. Do not paste access tokens into chat when this flow is available.

If `GH_TOKEN` or `GITHUB_TOKEN` is already set, it takes precedence over stored credentials. `agent-env github-auth` therefore refuses to start a competing stored-login flow until that environment token is fixed or unset. If a stored credential exists but is unusable, the command also refuses to overwrite it blindly; diagnose network/credential state with `agent-env github` first.

Do not pre-request broader OAuth scopes. If a concrete GitHub operation requires an additional scope, add only that scope with the normal `gh auth refresh` flow while the user is engaged, verify the operation, and continue. Git credential-helper configuration is intentionally separate; authentication does not silently rewrite host Git configuration.

A stored GitHub CLI token may fall back to plaintext storage when the host has no credential store. That is GitHub CLI behavior, not portable-bundle state. Review the host/session if persistence matters.

## Magnet Photos workflow

From a Magnet Photos checkout:

```bash
source /path/to/magnet-agent-env/activate
agent-env github      # only when GitHub is relevant to the turn
make doctor
make bootstrap
make check-fast
```

The bundle supplies the Node major required by the repository. `make bootstrap` still installs the exact **repository-pinned** Supabase CLI and Postgres language tooling from `package-lock.json`. Continue to use Magnet's Make targets rather than raw Supabase commands.

Full database checks still require a host-provided working Docker/Podman-compatible runtime.

## Mutable state

The verified payload is intended to stay stable. Runtime mutation belongs under `state/`:

- UV cache and ad-hoc UV tools
- ad-hoc UV-managed Python installations
- npm cache and global installs
- Python bytecode/cache state

This keeps experimentation from silently modifying the bundled Python or Node runtimes. Project dependencies still belong to the project itself.

Do not copy tokens, SSH keys, `.npmrc` credentials, cloud credentials or production database secrets into this directory.

## Portability contract

The bundle may be moved to a different pathname on a **compatible Linux x86-64 glibc host**. It is not cross-OS or cross-architecture.

The environment combines `uv venv --relocatable` with a location-aware Python wrapper because the venv still needs to identify its bundled base interpreter after relocation. The builder also normalizes uv-managed Python sysconfig install-prefix metadata into a location-neutral form, so `sysconfig` continues to resolve the relocated bundled runtime correctly without making that file mutable. Build-time tests reject absolute symlinks and stale references to prior build locations, then move, self-test, destroy/rebuild the Python venv offline, archive, extract and test again.

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
