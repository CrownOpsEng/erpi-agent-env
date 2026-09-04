# ERPI Agent Environment Builder

Builds a **portable Linux x86-64 AI-agent execution environment** for repositories where an agent has shell access but the host is missing useful tooling.

The bundle is deliberately external to target-project application/dependency models. Target repositories remain authoritative for their own dependencies, safety rules, command surfaces, schemas, migrations, and application architecture.

The design target is high-leverage asymmetry: solve recurring execution-environment limitations once while keeping the permanent control surface small.

## Agent routing

The shipped runtime has a short root `AGENTS.md`. Agents should read that router first; they do not need build archaeology or this manual for ordinary work. The router preserves target-project authority, diagnoses uncertain host capability with `agent-env doctor`, and routes GitHub-dependent work through `agent-env github` before substantial remote work.

A working bundled `gh` binary does **not** imply the shell can reach GitHub. `agent-env github` probes shell reachability first. If the host/sandbox blocks GitHub, it returns exit `3`, tells the agent not to keep retrying shell `gh`/GitHub Git, preserves local Git as usable, and points to a platform GitHub connector/app when available. If that connector can download a repository-owned Git handoff artifact, `agent-env git-handoff restore` validates and reconstructs it locally so subsequent editing, diffs, tests, and Git semantics stay in the execution environment.

## Payload

The finished bundle pins and verifies a deliberately small generic capability layer:

- uv 0.12.5 and uv-managed CPython 3.13.14 from an explicitly pinned python-build-standalone build
- Node.js 24.19.0 LTS with npm/npx
- GitHub CLI, jq, yq, ripgrep, actionlint, gitleaks, ShellCheck, and Miller
- a bounded Git-bundle handoff restorer that turns connector-downloaded repository artifacts into verified local worktrees without shell GitHub networking or credentials
- a locked Python analysis layer with the HTTPX CLI completed, without project-specific pytest/setuptools/wheel requirements
- PostgreSQL 17.10 server plus explicitly routed client/test/recovery tools, pgTAP 1.3.3, and plpgsql_check 2.8.11
- Supabase CLI 2.114.0 from the exact official Linux amd64 release archive, with its matched `supabase-go` companion and host/session credentials preserved outside the bundle
- PostgREST 14.16 as the exact official static Linux x64 native default selected by Supabase CLI 2.114.0, exposed only through a loopback-only local execution wrapper
- a plan-only `@supabase/pg-delta` 1.0.0-alpha.33 runtime, qualified against Supabase CLI 2.114.0 and restricted to numeric-loopback PostgreSQL URLs
- exact offline npm capability capsules for postgres 3.4.7, PostgreSQL Language Server WASM 0.25.7, fast-check 4.9.0, and pure-rand 8.4.2

PostgreSQL is intentionally **not** placed on the activated `PATH`; use `agent-env pg TOOL ...`. `agent-env pg-delta plan` exposes only schema-plan generation; the upstream `apply`/`sync` CLI is not shipped as an operator surface, and live URLs are limited to numeric loopback. The npm capsules are offline inputs, not a second project dependency authority. The Supabase CLI is bundled, but its container-backed local stack still requires a host Docker-compatible runtime; Kong, Auth, Storage, project-specific Supabase tooling, application frameworks, project test frameworks, Git, Make, and Docker/Podman remain project/host concerns. Standalone PostgREST is promoted only as the generic HTTP-to-PostgreSQL request-semantics discriminator; it is not managed Supabase parity.

## Portability model

Relocation uses self-locating repair of the venv base-Python `home` while `uv venv --relocatable` owns standard activation/entrypoint portability. The bundle repairs only the one `pyvenv.cfg` value that cannot remain valid when the bundled interpreter itself moves, and stale build-root residue is a hard failure.

The uv-managed python-build-standalone runtime remains intact under `runtime/python/`; the venv reaches it through relative internal topology. The selected distribution's exact build identifier, upstream URL and SHA-256 are pinned in `versions.env`, asserted against the installed runtime's `BUILD` file, and copied into runtime provenance. uv install-time sysconfig prefix metadata is normalized into a location-derived form so the base runtime can move without making sysconfig mutable.

The supported runtime contract is GNU/Linux x86-64 with kernel >= 4.18, glibc >= 2.28, and libstdc++ exposing `GLIBCXX_3.4.25`. It is not Windows/macOS/ARM/musl portability.

## Build

Prerequisites: supported GNU/Linux x86-64, Bash, curl, GNU tar, xz/bzip2, sha256sum, find, sed/awk/grep, Git history containing the reachable version tags, a working Docker daemon, and internet access. Exported source trees without `.git` must provide the full `ERPI_AGENT_SOURCE_COMMIT`, `ERPI_AGENT_SOURCE_BASE_TAG`, `ERPI_AGENT_SOURCE_DISTANCE`, and `ERPI_AGENT_SOURCE_DESCRIPTION` tuple. No sudo is used. Docker is a builder capability only; it is not bundled into the runtime.

```bash
./tests/static-check.sh
./build.sh
```

`PRODUCT_VERSION` in `versions.env` is the product/build SemVer authority. Stable development may retain the released version, while corrections after a published prerelease use a numeric candidate-build revision such as `0.3.0-rc.1-1`. Git ancestry remains the exact source authority, and the builder derives artifact identity from the nearest reachable stable/prerelease tag, commit distance, and source SHA:

```text
stable descendant: erpi-agent-env-linux-x64-v0.1.1-17-g4c2fa17c9a1.tar.gz
exact RC:          erpi-agent-env-linux-x64-v0.2.0-rc.1.tar.gz
RC descendant:    erpi-agent-env-linux-x64-v0.2.0-rc.1-2-g91ab3c4d5e6f.tar.gz
exact stable:      erpi-agent-env-linux-x64-v0.2.0.tar.gz
```

This is Git source identity, not invented SemVer. The numeric distance makes development order visible; the full 40-character source SHA, base tag, distance and source description are recorded in `manifest/environment.json` and `acceptance.json`; the archive SHA-256 identifies the exact bytes.

There is no `-dev` product version. After a published prerelease, corrections use numeric candidate-build revisions such as `0.3.0-rc.1-1`; those builds are development only and never trigger a tag or Release. The clean next RC is cut only after a revisioned build has passed the required real-world qualification, using a release-metadata-only `PRODUCT_VERSION`/release-request promotion change and immutable `v$PRODUCT_VERSION` tag. The release cut itself does not require a dedicated PR.

Archive creation normalizes tar ordering/metadata, gzip headers, and the relocatable `pyvenv.cfg` placeholder so repeated packaging of the same accepted payload is byte-for-byte deterministic.

Use `./build.sh --help` for output/cache options. Direct downloads, uv's managed-Python archive cache, uv's build cache, and pip's download cache are kept under `.download-cache/` and are never shipped. GitHub Actions derives the shared download-cache key with `scripts/download-cache-key.sh` from dependency/build-input pins plus `requirements.lock`; product-version/archive metadata such as `PRODUCT_VERSION` does not churn that cache, while every reused artifact is still verified by its own pinned hash before use.
The PostgreSQL server is built during every full acceptance/distribution build from the exact official PostgreSQL 17.10 source tarball inside a digest-pinned manylinux 2.28 image. PostgreSQL 17.10 regenerates scanner sources during this build, so the exact qualified AlmaLinux `flex-2.6.1-9.el8.x86_64` RPM is a pinned build-only input: its SHA-256 is verified, its package identity/signature are checked inside the pinned image, it is installed from local bytes with container networking disabled, and it is not shipped in the runtime. The builder keeps the normal installed PostgreSQL prefix and deterministic GNU `ar` mode; optional readline, zlib, and ICU integrations are disabled only to reduce external runtime dependencies. The source-controlled PostgreSQL client/plpgsql_check payloads remain separately qualified inputs and can be reproduced with `scripts/rebuild-qualified-database-assets.sh` using the same pinned/offline PostgreSQL build prerequisites.

Direct third-party license/attribution texts for redistributed command/database/capsule/library components are source-controlled under `vendor/licenses/` and copied into the runtime. ShellCheck is handled additionally under its GPL corresponding-source obligations: the runtime carries its license and exact pinned upstream source archive under `licenses/`. PostgreSQL server provenance terminates at the pinned official source artifact and pinned build image rather than an opaque prebuilt server bundle; the official PostgreSQL copyright notice is retained in the runtime.


## Offline Node capsule boundary

The target repository's `package-lock.json` remains authority. The capsule set includes `yaml` 2.9.0 for repositories that lock that exact package, alongside the existing database and test-library capsules. `versions.env` pins the immutable capsule hashes and package versions used by the generic runtime; `vendor/node-capsules/manifest.json` is the source-controlled package/integrity manifest, the builder validates it against those pins before copying it to `manifest/node-capsules.json`, and source validation verifies the pins against both that manifest and the actual capsule bytes.

Hydration is deliberately transactional and repository-contained. It validates all destinations before writing, rejects symlinked `node_modules` or scope parents and any resolved target outside the repository, stages every missing package before committing any of them, runs no lifecycle scripts, and does not claim packages already owned by the project. Agent-owned packages are recorded with deterministic content hashes; cleanup first verifies every record and refuses the entire operation if any owned package was replaced or modified. Dedicated negative tests preserve these invariants.

## Acceptance

The builder does not report success unless it verifies native assets and source-controlled capsule/license inputs; creates the environment under hostile pathnames; builds the venv with uv relocation support; uses the source-frozen hashed Python lock; asserts exact managed-Python provenance; rejects absolute symlinks and old build-root residue; relocates to a deep Unicode/spaces path; exercises compiled Python code, HTTPX/ShellCheck/Miller, real offline Node capsule hydration/import/cleanup, and the PostgreSQL capability; destroys/rebuilds Python offline; exercises pgTAP failure handling, plpgsql_check, pg-delta source→target→clone convergence and remote-target refusal, real PostgREST role impersonation/pre-request/RPC privilege behavior plus remote-target refusal and signal cleanup, Supabase CLI relocation/version/init/migration behavior with its pinned Go companion, dump/restore, pg_amcheck, pgbench, child-exit propagation and signal cleanup; canonicalizes uv's optional timestamp metadata; verifies immutable files and symlink topology; validates the source TSV and third-party material; resets mutable state; archives; freshly extracts; and verifies again.

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
agent-env git-handoff restore ARTIFACT.zip DEST
```

`github-git` installs only a repo-local, location-neutral `!gh auth git-credential` helper and verifies the push path with `git push --dry-run --no-verify`. The bundle does not use `gh auth setup-git`, which would persist the relocatable `gh` executable's current absolute path globally.

`git-handoff restore` is intentionally credentialless and networkless. It accepts only the generic four-file Git-bundle ZIP contract, requires host Git, verifies the bundle is self-contained and that the declared branch resolves to the declared source SHA, isolates Git from inherited/global/system configuration, restores ordinary history/tags/remote-tracking refs, writes only the canonical GitHub origin/upstream configuration, and fails cleanly. Artifact generation remains a target-repository/GitHub concern rather than becoming a hidden second clone mechanism inside this environment.

## Mutable state and security boundary

Ad-hoc uv tools/Pythons, npm globals, caches, and Python bytecode go under `state/`. The release archive always ships pristine mutable state. Once populated, `state/` is per-location/disposable; third-party installers may create location-specific links that should be recreated after moving an already-used bundle.

The package expands commands available **within permissions the host already grants**. It cannot manufacture network access, GitHub credentials, a Docker daemon/socket, filesystem execution permission, kernel capabilities, or unsupported OS/CPU compatibility.

## Repository automation

Normal changes use topic branches and pull requests. Branch commits are detailed semantic checkpoints; the PR synthesizes the review unit and records one `Internal` / `Fix` / `Additive` / `Breaking` compatibility assessment; integration is a squash merge so `main` stays a sequence of coherent completed changes.

The permanent workflows are:

- **Validate** — source/static checks plus commit-history and PR-description policy on pull requests and `main`.
- **Accept runtime** — full hydration/relocation/offline-rebuild/archive acceptance for payload-affecting `main` changes and deliberate runtime proof.
- **Publish release** — stable/prerelease gate for an exact accepted source. It creates/verifies immutable `v$PRODUCT_VERSION`, prepares/reuses the matching draft Release, and marks prerelease versions as GitHub prereleases.
- **Build distribution** — full tagged build. It verifies tag/SHA/product-version agreement, attaches archive/checksum/`acceptance.json`, then publishes the draft.

For connector-only AI sessions, `.github/release-request.json` remains the auditable release command. `CONTRIBUTING.md` owns the exact record/version/release procedure. Enabling GitHub release immutability is recommended so published tags/assets cannot be altered.
