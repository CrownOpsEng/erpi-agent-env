# Magnet Agent Environment Builder

Builds a **portable Linux x86-64 AI-agent execution environment** for Magnet Photos and similar repositories when an agent has shell access but the host is missing useful tooling.

The bundle is deliberately external to the Magnet Photos application/dependency model. Target repositories remain authoritative for their own dependencies, safety rules, command surfaces, schemas, migrations, and application architecture.

The design target is high-leverage asymmetry: solve recurring execution-environment limitations once while keeping the permanent control surface small.

## Agent routing

The shipped runtime has a short root `AGENTS.md`. Agents should read that router first; they do not need build archaeology or this manual for ordinary work. The router preserves target-project authority, diagnoses uncertain host capability with `agent-env doctor`, and routes GitHub-dependent work through `agent-env github` before substantial remote work.

A working bundled `gh` binary does **not** imply the shell can reach GitHub. `agent-env github` probes shell reachability first. If the host/sandbox blocks GitHub, it returns exit `3`, tells the agent not to keep retrying shell `gh`/GitHub Git, preserves local Git as usable, and points to a platform GitHub connector/app when available.

## Payload

The finished bundle pins and verifies:

- uv 0.12.5
- uv-managed CPython 3.13.14
- Node.js 24.19.0 LTS with npm/npx
- GitHub CLI 2.97.0
- jq 1.8.2
- yq 4.53.3
- ripgrep 15.2.0
- actionlint 1.7.12
- gitleaks 8.30.1
- a small locked Python analysis layer including httpx, jsonschema, packaging, PyYAML, tomlkit and pytest

It intentionally does **not** bundle Supabase, the Postgres language server, Git, Make, Docker/Podman, or PostgreSQL client tooling. Supabase/PGLS are project-owned; Git/Make are host prerequisites; a Docker client without a usable daemon is false capability; and direct database tooling could bypass repository-owned safe command surfaces.

## Portability model

The J2911 portable venv was used as a reference. Its strongest idea—self-locating repair of the venv base-Python `home` after a move—is retained. Its stale absolute console-script failure is not: `uv venv --relocatable` owns standard activation/entrypoint portability, the bundle repairs only the one `pyvenv.cfg` value that cannot remain valid when the bundled interpreter itself moves, and stale build-root residue is a hard failure.

The uv-managed python-build-standalone runtime remains intact under `runtime/python/`; the venv reaches it through relative internal topology. uv install-time sysconfig prefix metadata is normalized into a location-derived form so the base runtime can move without making sysconfig mutable.

The supported runtime contract is GNU/Linux x86-64 with kernel >= 4.18, glibc >= 2.28, and libstdc++ exposing `GLIBCXX_3.4.25`. It is not Windows/macOS/ARM/musl portability.

## Build

Prerequisites: supported GNU/Linux x86-64, Bash, curl, GNU tar, xz, sha256sum, find, sed/awk/grep, and internet access. No sudo is used.

```bash
./tests/static-check.sh
./build.sh
```

The artifact name is derived from `BUNDLE_VERSION` in `versions.env`:

```text
magnet-agent-env-linux-x64-v<version>.tar.gz
magnet-agent-env-linux-x64-v<version>.tar.gz.sha256
```

Use `./build.sh --help` for output/cache options. Direct downloads, uv's managed-Python archive cache, uv's build cache, and pip's download cache are kept under `.download-cache/` and are never shipped.

## Acceptance

The builder does not report success unless it verifies native assets; creates the environment under hostile pathnames; builds the venv with uv relocation support; uses the source-frozen hashed Python lock; rejects absolute symlinks and old build-root residue; relocates to a deep Unicode/spaces path; exercises compiled Python code and uv-generated console entrypoints; destroys/rebuilds Python offline; canonicalizes uv's optional timestamp metadata; verifies immutable files and symlink topology; resets mutable state; archives; freshly extracts; and verifies again.

`VALIDATION.md` defines the current evidence/authority model. It is intentionally **not** a per-build ledger. Successful **Accept runtime** runs generate machine-readable `acceptance.json` evidence; published GitHub Releases carry the authoritative archive, checksum sidecar, and acceptance metadata. Change rationale remains in Git history, execution evidence remains in GitHub Actions, and superseded narrative records are removed from the live tree once they stop serving current operation.

## Python lock and build isolation

`requirements.lock` is source-controlled input, not generated during hydration. Its exact 21-package hashed resolution and its own SHA-256 are pinned. Changing the lock is an intentional builder change, not an ambient resolver event.

Builder/recovery uv invocations ignore project/user uv configuration and Python artifact-selection overrides while preserving ordinary proxy and CA/system-certificate transport settings. The temporary pip bootstrap wheel is fetched from an exact PyPI file URL and SHA-256 verified before execution.

uv writes optional `*.dist-info/uv_cache.json` metadata containing installation time. Runtime self-test removes that nonfunctional cache record and its corresponding `RECORD` row so an offline rebuild restores the same checksum-covered venv.

## GitHub authentication

Credentials are demand-driven host/session state and are never bundled.

```bash
agent-env github
agent-env github-auth   # only when network is reachable and no usable credential exists
agent-env github-git    # for an HTTPS GitHub worktree that will push
```

`github-git` installs only a repo-local, location-neutral `!gh auth git-credential` helper and verifies the push path with `git push --dry-run --no-verify`. The bundle does not use `gh auth setup-git`, which would persist the relocatable `gh` executable's current absolute path globally.

## Mutable state and security boundary

Ad-hoc uv tools/Pythons, npm globals, caches, and Python bytecode go under `state/`. The release archive always ships pristine mutable state. Once populated, `state/` is per-location/disposable; third-party installers may create location-specific links that should be recreated after moving an already-used bundle.

The package expands commands available **within permissions the host already grants**. It cannot manufacture network access, GitHub credentials, a Docker daemon/socket, filesystem execution permission, kernel capabilities, or unsupported OS/CPU compatibility.

## Repository automation

This repository is intentionally direct-to-`main`; PRs remain optional for explicit review/isolation. The permanent workflows are:

- **Validate** — cheap source/static checks on every `main` push, optional PRs, and manual runs.
- **Accept runtime** — full hydration/relocation/offline-rebuild/archive acceptance after payload-affecting `main` changes; retains only small checksum/`acceptance.json` evidence.
- **Publish release** — manual or connector-triggered release gate. It resolves an exact accepted source commit, verifies **Accept runtime**, creates or verifies the exact release Git tag, and then creates or reuses the matching draft Release.
- **Build distribution** — full tagged release build. It verifies the checked-out tag and mutable draft, attaches the archive, checksum and `acceptance.json`, and only then publishes the Release; it can also build a short-lived Actions artifact without a release tag.

For connector-only AI sessions, `.github/release-request.json` is the durable release command. `CONTRIBUTING.md` documents its exact schema and the release flow.

GitHub recommends draft-first publishing when release immutability is enabled because assets must be attached before publication. The workflow is designed for that model. Enabling repository **release immutability** is recommended for future releases so published tags/assets cannot be altered.
