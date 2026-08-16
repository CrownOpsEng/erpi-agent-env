# Magnet Agent Environment Builder v1

Builds a **portable Linux x86-64 agent execution environment** intended to be uploaded/mounted beside Magnet Photos and used by ChatGPT/Codex-style shell agents.

It is deliberately **not part of the Magnet Photos application or dependency model**. Magnet's repository remains authoritative for its own Supabase CLI, Postgres language tooling, checks, schemas, migrations, and future application stack.

The design target is high-leverage asymmetry: solve recurring agent-environment limitations once, while keeping the permanent control surface small.

## Design

The runtime has a short root `AGENTS.md` router. Agents do not need to load the build history or this manual for ordinary project work. Detailed operation remains discoverable through `agent-env help`, `README.md`, and `manifest/` only when needed.

The J2911 portable venv was used as a reference. Its strongest idea—self-locating repair of the venv's base-Python `home` after a move—is preserved. Its main portability weakness is not: a stale absolute path was found in an installed console script after relocation. This builder therefore lets `uv venv --relocatable` own standard entrypoint/activation portability, patches only the one `pyvenv.cfg` value uv cannot keep valid when the bundled base interpreter itself moves, and treats **old build-root residue as a hard failure**.

The bundled uv-managed python-build-standalone runtime is kept intact under `runtime/python/`; the venv reaches it through a relative internal link. uv's install-time sysconfig prefix is normalized once into a location-derived form so the base runtime can move without making sysconfig mutable.

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

Prerequisites: supported GNU/Linux x86-64 with **kernel >= 4.18, glibc >= 2.28**, Bash, curl, GNU tar, xz, sha256sum, find, sed/awk/grep and internet access. The Node 24.19.0 official x64 binary also requires libstdc++ exposing **GLIBCXX_3.4.25** (libstdc++ >= 6.0.25). Ubuntu 20.04+/Debian 10+/RHEL 8+ class hosts and suitable WSL2 x86-64 environments meet this target. No sudo is used. The finished runtime assumes ordinary Linux base utilities such as `find`, `sha256sum`, `cmp`, and `diff`; these are diagnosed rather than duplicated.

```bash
./tests/static-check.sh
./build.sh
```

By default the finished artifact is written under `dist/` as:

```text
magnet-agent-env-linux-x64-v1.0.0.tar.gz
magnet-agent-env-linux-x64-v1.0.0.tar.gz.sha256
```

Use `./build.sh --help` for output/cache options. Direct downloads (including the verified pip bootstrap wheel), uv's managed-Python archive cache, uv's build cache, and pip's download cache are kept under the builder's `.download-cache/`, separate from the finished environment. A failed build can therefore be resumed without redownloading CPython or other already-fetched artifacts and without trusting partial payload files.

## Acceptance

The builder does not report success unless it:

1. verifies downloaded native artifacts;
2. creates the environment under a path containing spaces;
3. builds the Python venv with native uv relocation support;
4. verifies the source-frozen hashed Python lock and creates an offline wheelhouse without resolving dependency versions;
5. rejects absolute symlinks and old build-root residue;
6. relocates to a deep path containing spaces and Unicode and self-tests;
7. destroys/rebuilds the Python venv offline, canonicalizes uv's optional timestamp-bearing install metadata, and self-tests again before immutable verification;
8. emits and verifies immutable-file and symlink manifests;
9. directly exercises uv-generated `pip`/`pytest` console entrypoints and compiled Python extensions after relocation/rebuild;
10. archives, freshly extracts, self-tests and verifies the final artifact.

See `VALIDATION.md` for source-level evidence, connected-host acceptance, and release-candidate artifact checksums.

## Python lock and build isolation

`requirements.lock` is an input to v1, not generated during hydration. It is the exact 21-package hashed resolution captured from the first connected build under the recorded cutoff, and its own SHA-256 is pinned in `versions.env`. Updating that lock is therefore an intentional builder-version change rather than an ambient resolver event.

Builder/recovery uv invocations run through a small isolation wrapper that ignores project/user uv configuration and Python artifact-selection overrides while preserving ordinary proxy and CA/system-certificate transport settings. The one temporary pip bootstrap wheel is fetched from its exact PyPI file URL and SHA-256 verified before any pip code executes; it then remains in the offline wheelhouse.

uv also writes optional `*.dist-info/uv_cache.json` installer-cache metadata containing the installation timestamp. Runtime self-test removes that nonfunctional cache record and its corresponding `RECORD` row, so an offline rebuild restores the same checksum-covered venv rather than differing only because it happened later.

## Security boundary

This increases the commands an agent can execute **inside permissions the sandbox already grants**. It cannot create network access, a Docker daemon, credentials, kernel capabilities, or filesystem permissions that the host denies.

Ad-hoc UV Python installs, UV tools, npm globals and caches are redirected to `state/` so they do not mutate the verified bundled runtimes. Build-time self-tests intentionally exercise that state, but the distributable archive is always produced with a pristine empty `state/` tree; runtime caches are first-use state, not payload. Do not place credentials or production secrets inside the bundle.

## Repository automation

This repository is intentionally **direct-to-`main`**. Pull requests remain available when explicit review or isolation is useful, but they are not required for the normal single-owner workflow. Three GitHub Actions workflows provide the safety boundary instead:

- **Validate** runs `./tests/static-check.sh` on every push to `main` and can also be run manually.
- **Accept runtime** runs the full hydration → relocation → offline destruction/rebuild → archive/extraction acceptance sequence after payload-affecting pushes to `main`. It records the resulting digest but does not publish the 154 MB artifact.
- **Build distribution** is manual or runs when a GitHub Release is published. It repeats the full acceptance build, uploads the `.tar.gz` plus `.sha256` as an Actions artifact, and attaches those files to the Release when release-triggered.

This keeps ordinary documentation/policy commits lightweight, gives direct-to-main payload changes a real post-push integration proof, and keeps distribution creation an explicit release concern.
