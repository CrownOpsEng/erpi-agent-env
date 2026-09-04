# Validation contract

This file defines the stable validation authority for ERPI Agent Environment. Git history records changes; GitHub Actions and release assets record execution/publication evidence. Do not maintain a second hand-written run ledger here.

## Source validation

`./tests/static-check.sh` is the fast source gate. It must fail closed on malformed scripts, inconsistent pins/locks, missing required source, unsafe credential handling, router ownership/structure drift, invalid portability assumptions, mismatched source-controlled qualified native payloads, malformed provenance metadata, incomplete required direct-license material, and unsafe Node-capsule filesystem/ownership behavior.

Source validation does not prove the runtime.

## Runtime acceptance

A payload-affecting source commit is releasable only after **Accept runtime** builds the complete archive from that exact commit and the resulting runtime passes all builder gates, including:

- verified upstream/custom payload hashes before execution or inclusion
- supported Linux x86-64/glibc host contract
- exact managed-Python build provenance plus Python relocation repair, native-import checks, and offline venv destruction/rebuild
- bundled command functional probes, including ShellCheck positive/negative behavior, Miller transformation, HTTPX CLI localhost execution, and host-Git-backed connector handoff restoration when Git is available
- exact-lock offline Node capsule hydration using the real bundled packages, content-bound ownership, import execution, and safe cleanup
- source-level Node-capsule negative tests for lock mismatch, all-or-nothing late conflicts, symlinked `node_modules`/scope escape attempts, stale ownership, pre-existing repository packages, and legacy-marker refusal
- PostgreSQL server/client version and extension integration checks
- disposable PostgreSQL start/query, pgTAP positive/negative accounting, plpgsql_check, dump/restore, `pg_amcheck`, pgbench, and stopped-cluster checksum verification when the acceptance host is unprivileged
- PostgreSQL child-exit propagation and signal-interrupted teardown with no orphaned cluster state or occupied loopback port
- exact pg-delta lock/API installation, plan-only routing, numeric-loopback refusal boundary, representative source→target→clone convergence, managed-schema filtering, and empty convergence re-plan
- exact PostgREST upstream asset/version/static-binary provenance, numeric-loopback database refusal, loopback-only HTTP binding, real request-role impersonation/search-path/pre-request semantics, SECURITY DEFINER→SECURITY INVOKER success and SQLSTATE `42501` negative behavior over HTTP, plus interrupted-process cleanup
- exact Supabase CLI 2.114.0 official Linux amd64 archive integrity, paired `supabase`/`supabase-go` runtime, supported-host GLIBC floor, relocation-safe companion routing, version probes, and filesystem-only `init`/`migration new` behavior under non-interactive stdin without bundled credentials or container-runtime assumptions
- hostile relocation with spaces/unicode/deep paths
- PostgreSQL lifecycle under that hostile relocation path over explicit `127.0.0.1` TCP with Unix-domain sockets disabled, preventing relocation depth from becoming a socket-path failure mode
- rejection of original build-root residue and absolute symlinks
- pristine mutable state before packaging and no group/world-writable immutable regular files
- immutable checksum/symlink manifest verification
- parseable four-column `manifest/sources.tsv` and bundled direct third-party compliance material required by the builder contract, including ShellCheck corresponding source/license
- deterministic archive ordering/timestamps/gzip metadata and a stable first-use `pyvenv.cfg` sentinel
- fresh archive extraction, repair, self-test, and stale-path rejection

The accepted archive hash and exact source SHA belong in machine-generated `acceptance.json` and the archive sidecar, not copied into narrative docs.

## PostgreSQL source/native qualification

The PostgreSQL server is not accepted from a prebuilt third-party binary bundle. Every full runtime build fetches the exact pinned official PostgreSQL source tarball, verifies its SHA-256, and builds the normal install prefix inside a digest-pinned manylinux 2.28 image. PostgreSQL 17.10's normal build regenerates scanner sources, so its Flex prerequisite is also immutable: the builder verifies the exact pinned AlmaLinux `flex-2.6.1-9.el8.x86_64` RPM SHA-256 and package identity/signature, installs that local RPM without dependency resolution or package scripts, and disables container networking for the PostgreSQL compilation. Flex is a build input recorded in provenance, not redistributed runtime payload. Deterministic GNU `ar` mode (`AROPT=crsD`) is required for PostgreSQL static archives. Optional readline, zlib, and ICU integrations are disabled to avoid unnecessary external runtime-library dependencies; the resulting ELF symbol floor and dynamic dependencies are checked before runtime acceptance.

The source-controlled PostgreSQL client and plpgsql_check payloads are qualified build inputs. Their pinned hashes are validated by source checks and by `build.sh` before extraction. They are qualified from a controlled GLIBC 2.28 build using pinned PostgreSQL 17.10/plpgsql_check sources; maximum GLIBC requirements are 2.25 for the client payload and 2.17 for plpgsql_check. `scripts/rebuild-qualified-database-assets.sh` provides their pinned maintainer reproduction path.

Any future server source, configure, build-image, Flex build-input, client, or extension-native change requires full source validation and runtime acceptance. A harness defect is fixed and the complete relevant qualification is rerun; partial progress is not promoted as success.

## Node capsule boundary

Offline Node capsules supply immutable bytes only when a target repository's lock requests the exact pinned version and npm integrity. They never become dependency authority.

Hydration must remain repository-contained and transactional: validate every destination and capsule before writing; reject symlink/path escapes; stage all missing packages before any commit; never claim matching packages that already belong to the repository; and write content-bound ownership only after successful commit. Cleanup must verify all recorded ownership before deleting anything and fail closed if the package contents or marker cannot be trusted.

Any change to this boundary requires the dedicated source-level negative suite plus real runtime hydration/import/cleanup acceptance. A happy-path package import alone is not sufficient evidence.

## Long-running commands and supervision

Do not change the logical shape of a repository acceptance run merely because an agent execution wrapper has a shorter foreground window.

Execution order:

1. Use one repository-owned validation command with an adequate outer timeout when supported.
2. Otherwise keep that same process in a persistent terminal/session and poll it.
3. If sessions are unavailable, supervise one child process and poll the same PID/output until its real exit status is available.
4. Split only repository-defined independent phases or deliberate failure-isolation work.

Timeout ordering must preserve inner failure semantics:

```text
database lock/statement timeouts < repository watchdog < outer execution supervision
```

A wrapper timeout is environmental evidence, not a test failure or success.

## pg-delta compatibility boundary

The shipped pg-delta capability is intentionally narrower than the upstream CLI. `@supabase/pg-delta` is pinned exactly to `1.0.0-alpha.33`, with its complete npm lock and package integrity/license provenance, because that is the qualified default for Supabase CLI 2.114.0. Promotion requires useful and safe schema planning for the motivating consumer workflows; it does not require perfect behavioral parity with every Supabase CLI wrapper option.

Only `agent-env pg-delta plan` is exposed. Live source and target URLs must be numeric loopback, inherited PostgreSQL targeting variables are scrubbed, and upstream mutation commands such as `apply` or `sync` are not routed. Acceptance proves a representative plan can be generated without mutating source/target, applied by the test harness to a clone, and then converges to an empty re-plan. Any pg-delta version or compatibility-baseline change requires fresh qualification before promotion.

## PostgREST compatibility boundary

PostgREST 14.16 is pinned because it is the exact upstream native default selected for Linux x64 by the qualified Supabase CLI 2.114.0 baseline. The environment exposes only a bounded local execution surface: database URLs must remain numeric loopback, the HTTP listener is fixed to loopback, inherited `PGRST_*` configuration is scrubbed, and project-supplied schemas, roles, pre-request functions and RPCs remain target-repository state.

Acceptance must exercise the real PostgREST process rather than replacing it with `SET ROLE` or direct SQL. It proves request-role/session-role context, request search path, a configured generic pre-request function, and a SECURITY DEFINER wrapper calling a SECURITY INVOKER dependency in both a correctly granted path and a deliberately missing-schema-privilege path that surfaces SQLSTATE `42501` over HTTP. It also proves remote database refusal and signal cleanup.

This capability is a discriminator for ordinary PostgREST semantics, not a claim of managed Supabase parity. Kong routing, Supabase Auth/API keys, Storage, Realtime and other provider topology remain outside the bundle. A PostgREST version or compatibility-baseline change requires fresh upstream-asset and runtime qualification before promotion.


## Supabase CLI compatibility boundary

Supabase CLI 2.114.0 is redistributed from the exact official Linux amd64 release archive as a paired runtime: the TypeScript/Bun `supabase` executable plus its matched `supabase-go` companion. The user-facing `supabase` wrapper resolves the bundle root at invocation time and exports only `SUPABASE_GO_BINARY` to the private companion path; `supabase-go` is not added to ambient `PATH`. `HOME`, XDG state, access tokens, database passwords, project links, and other credentials remain host/session state and are never redirected into immutable payload paths or bundled.

Promotion does not claim that the portable environment supplies the full local Supabase stack by itself. Filesystem-only CLI behavior must work after hostile relocation without Docker or network access; stack-backed commands such as `supabase start`, local database lifecycle, containerized dump/diff paths, and service orchestration still require a usable host Docker-compatible runtime. Remote operations still require the host network and credentials the target repository/user intentionally provides.

Acceptance verifies the exact archive hash and two-file distribution shape, both embedded version identities, the primary executable's GLIBC requirement against the environment floor, private companion routing, and real `supabase init` plus `supabase migration new` filesystem effects with stdin closed so non-interactive tests cannot hang waiting for input. Any Supabase CLI version, archive, companion-routing, or supported-host dependency change requires fresh qualification before promotion.

## Git handoff boundary

The environment owns only the local restore side of repository handoff. A standard artifact is a ZIP containing exactly `repository.bundle`, `SOURCE_SHA`, `SOURCE_BRANCH`, and `REPOSITORY`; producer workflows and connector download behavior remain target-repository/platform concerns.

Restore must require host Git but no shell network or credential; reject malformed, duplicate, traversal/unexpected, encrypted, or symlink-like ZIP entries; validate canonical metadata and branch syntax before repository creation; verify the bundle in an empty repository so prerequisite/incremental bundles fail; require the declared branch tip to equal the declared source SHA; isolate all Git operations from inherited/global/system configuration; reconstruct refs from local bundle bytes only; establish only a canonical GitHub HTTPS origin and matching upstream; run repository integrity and clean-worktree checks; refuse an existing destination; and remove staged state after any failed restore.

Source validation covers positive multi-commit/multi-branch/tag restoration plus malformed metadata, branch/SHA mismatch, prerequisite bundles, unsafe ZIP members, hostile Git configuration, and destination refusal. Runtime acceptance exercises the shipped `agent-env git-handoff restore` command using a real locally generated full bundle. The capability is transport plumbing, not GitHub authentication and not a substitute for target-repository authority.

## Consumer promotion proof

A reusable environment capability is not proven useful merely because its standalone self-test passes. When a capability is motivated by a specific consuming repository, release qualification must additionally exercise that repository's current authoritative interfaces/tests before the environment release is published.

That consumer proof should use the repository's real pinned client dependency and existing suites unchanged wherever possible. The environment must not carry project schema, business logic, roles, migrations, or test expectations solely to manufacture a passing result.

## Source identity and release boundary

`PRODUCT_VERSION` is released compatibility identity. It contains only stable SemVer or an intentional `alpha.N` / `beta.N` / `rc.N` prerelease. There is no pseudo-development version.

Git owns development source identity. For a clean committed source, the builder resolves the nearest reachable `v<SemVer>` tag, counts commits from that tag, and combines that ancestry with the exact source SHA. Exact tags produce the tag itself; descendants produce the Git-describe shape `vX.Y.Z[-prerelease]-N-g<abbrev>`.

This boundary is mechanical and must prove both stable and prerelease ancestry. In particular, source after `v0.2.0-rc.1` must describe from that RC (`v0.2.0-rc.1-1-g0123456789ab`, `v0.2.0-rc.1-2-g123456789abc`) rather than from the prior stable release or an invented `-dev` identity.

Runtime `manifest/environment.json` and generated `acceptance.json` record product version, full source commit, source description, base tag, and numeric distance separately. The archive filename uses the source description directly; the SHA-256 sidecar remains authority for exact archive bytes.

The builder refuses dirty worktrees. Exported source without `.git` must provide the complete source tuple (`ERPI_AGENT_SOURCE_COMMIT`, `ERPI_AGENT_SOURCE_BASE_TAG`, `ERPI_AGENT_SOURCE_DISTANCE`, and `ERPI_AGENT_SOURCE_DESCRIPTION`) because a SHA alone cannot reconstruct tag ancestry.

A `PRODUCT_VERSION` change is a dedicated release-metadata-only source change: `versions.env` and `.github/release-request.json` move together. It may be the single untagged release-cut commit ahead of the nearest existing tag; no later source commit may retain that ahead-of-tag product version. Once the matching tag is created, ordinary development may continue with the same product version and source descriptions anchored to that tag.

Source validation must reject backward product-version transitions, pseudo-development versions, version changes mixed with runtime/source changes, exact-tag/product-version disagreement, continuation after an untagged release-cut commit, and artifact/metadata names inconsistent with source ancestry.

## Release authority

Stable and prerelease tags are real immutable compatibility states. Optional prerelease stages mean `alpha.N` (materially incomplete target), `beta.N` (scope substantially complete while compatibility/qualification settles), and `rc.N` (intended release scope/contract frozen except release-blocking corrections). Stages are used only when they provide qualification value.

A release/prerelease requires:

1. the release-cut source change touches only approved release metadata and moves `PRODUCT_VERSION` forward;
2. source validation passes for the exact commit;
3. the exact payload-affecting source passes **Accept runtime** before publication;
4. permanent release workflow creates/verifies immutable `v$PRODUCT_VERSION` at that exact source and prepares a draft Release;
5. **Build distribution** checks out the real tag, requires source description to equal that tag, repeats full runtime acceptance, and attaches archive/checksum/`acceptance.json` before publication;
6. when a specific repository is the motivating consumer, current consumer promotion proof passes through repository-owned interfaces;
7. PostgreSQL/runtime provenance boundaries remain intact.

If an RC exposes a defect, its tag and published assets remain immutable. Keep the RC product version while fixing source; development descriptions attach to the RC tag. When ready, cut the next candidate with a release-metadata-only change (`rc.1` → `rc.2`). Do not increment PATCH for a defect in an unreleased target. If qualification shows the intended compatibility base is wrong, move to a new truthful base version.

Finalization from the accepted RC to stable is release-metadata-only and receives full proof again. Any runtime behavior change requires another RC.

No manual tag/upload path is authoritative. Temporary qualification workflows must not become an alternate release system.
