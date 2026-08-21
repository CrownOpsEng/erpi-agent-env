# Validation contract

This file defines the stable validation authority for Magnet Agent Environment. Git history records changes; GitHub Actions and release assets record execution/publication evidence. Do not maintain a second hand-written run ledger here.

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

The shipped pg-delta capability is intentionally narrower than the upstream CLI. `@supabase/pg-delta` is pinned exactly to `1.0.0-alpha.33`, with its complete npm lock and package integrity/license provenance, because that is the qualified default for Supabase CLI 2.114.0. Promotion requires useful and safe schema planning for the motivating Magnet Photos workflows; it does not require perfect behavioral parity with every Supabase CLI wrapper option.

Only `agent-env pg-delta plan` is exposed. Live source and target URLs must be numeric loopback, inherited PostgreSQL targeting variables are scrubbed, and upstream mutation commands such as `apply` or `sync` are not routed. Acceptance proves a representative plan can be generated without mutating source/target, applied by the test harness to a clone, and then converges to an empty re-plan. Any pg-delta version or compatibility-baseline change requires fresh qualification before promotion.

## PostgREST compatibility boundary

PostgREST 14.16 is pinned because it is the exact upstream native default selected for Linux x64 by the qualified Supabase CLI 2.114.0 baseline. The environment exposes only a bounded local execution surface: database URLs must remain numeric loopback, the HTTP listener is fixed to loopback, inherited `PGRST_*` configuration is scrubbed, and project-supplied schemas, roles, pre-request functions and RPCs remain target-repository state.

Acceptance must exercise the real PostgREST process rather than replacing it with `SET ROLE` or direct SQL. It proves request-role/session-role context, request search path, a configured generic pre-request function, and a SECURITY DEFINER wrapper calling a SECURITY INVOKER dependency in both a correctly granted path and a deliberately missing-schema-privilege path that surfaces SQLSTATE `42501` over HTTP. It also proves remote database refusal and signal cleanup.

This capability is a discriminator for ordinary PostgREST semantics, not a claim of managed Supabase parity. Kong routing, Supabase Auth/API keys, Storage, Realtime and other provider topology remain outside the bundle. A PostgREST version or compatibility-baseline change requires fresh upstream-asset and runtime qualification before promotion.

## Git handoff boundary

The environment owns only the local restore side of repository handoff. A standard artifact is a ZIP containing exactly `repository.bundle`, `SOURCE_SHA`, `SOURCE_BRANCH`, and `REPOSITORY`; producer workflows and connector download behavior remain target-repository/platform concerns.

Restore must require host Git but no shell network or credential; reject malformed, duplicate, traversal/unexpected, encrypted, or symlink-like ZIP entries; validate canonical metadata and branch syntax before repository creation; verify the bundle in an empty repository so prerequisite/incremental bundles fail; require the declared branch tip to equal the declared source SHA; isolate all Git operations from inherited/global/system configuration; reconstruct refs from local bundle bytes only; establish only a canonical GitHub HTTPS origin and matching upstream; run repository integrity and clean-worktree checks; refuse an existing destination; and remove staged state after any failed restore.

Source validation covers positive multi-commit/multi-branch/tag restoration plus malformed metadata, branch/SHA mismatch, prerequisite bundles, unsafe ZIP members, hostile Git configuration, and destination refusal. Runtime acceptance exercises the shipped `agent-env git-handoff restore` command using a real locally generated full bundle. The capability is transport plumbing, not GitHub authentication and not a substitute for target-repository authority.

## Project promotion proof

A generic environment capability is not proven useful to Magnet Photos merely because its standalone self-test passes. Database-capability releases must additionally be exercised against the target repository's current authoritative migrations/tests before the environment release is published when that project is the motivating consumer.

That project proof should use the repository's real pinned client dependency and existing suites unchanged wherever possible. The environment must not carry project schema, business logic, roles, migrations, or test expectations solely to manufacture a passing result.

## Build identity and candidate boundary

`BUNDLE_VERSION` carries compatibility/lifecycle state, not per-commit uniqueness. Source-controlled values are restricted to stable `X.Y.Z`, active-development `X.Y.Z-dev`, or candidate `X.Y.Z-rc.N`. Git owns exact source identity.

A distributable development build derives `BUILD_ID=X.Y.Z-dev+g<12-char-source>` from the exact 40-character source commit and names the archive `magnet-agent-env-linux-x64-v<BUILD_ID>.tar.gz`. Runtime `manifest/environment.json` and generated `acceptance.json` both retain the full source commit plus `build_id`; the archive SHA-256 remains authority for exact bytes. The `+g...` identifier is generated metadata and never belongs in `versions.env`.

The builder refuses a dirty Git worktree because uncommitted bytes cannot truthfully claim the checked-out commit identity. When building an exported source tree without `.git`, the caller must provide `MAGNET_AGENT_SOURCE_COMMIT=<40-hex-sha>` explicitly. When Git is available, any supplied source identity must exactly match `HEAD`.

Release-candidate and stable artifact filenames use only their SemVer identities because those identities are immutable. Commit-range validation mechanically rejects a second source commit retaining the same RC/stable version, requires RC cuts to be version-only transitions from matching `X.Y.Z-dev`, requires stable finalization to be a version-only transition from matching `X.Y.Z-rc.N`, and requires a rejected candidate to return to matching development state before further source changes.

A release candidate is not a debugging label. Before changing `BUNDLE_VERSION` from `X.Y.Z-dev` to `X.Y.Z-rc.N`, all known release blockers must be closed and the strongest relevant inexpensive/targeted checks must already pass. Pull-request validation and candidate acceptance remain different layers: `Validate` is normal source feedback; `Accept runtime` proves an exact committed runtime artifact.

## Release authority

A stable release requires a separately identified candidate first. Candidate builds use SemVer prerelease versions (`x.y.z-rc.N`) and are validation artifacts only; they must not create the stable tag or masquerade as `x.y.z`. After direct artifact verification, promote the source version to the stable `x.y.z` and accept that exact final commit again.

A release requires:

1. source commit passes source validation;
2. the exact payload-affecting source commit passes **Accept runtime**;
3. direct candidate artifact inspection finds no unresolved release blocker;
4. when Magnet Photos is the motivating consumer, current project promotion proof passes using the repository-owned interfaces;
5. release version is updated intentionally and is not a prerelease identifier;
6. permanent release workflow verifies the accepted source/tag relationship;
7. **Build distribution** rebuilds and accepts the tagged distribution before publication;
8. release assets include the archive, SHA-256 sidecar, and `acceptance.json`;
9. PostgreSQL server provenance remains pinned to the official source artifact and digest-pinned build image, with no opaque prebuilt server bundle or unresolved runtime dependency reintroduced.

No manual tag/upload path is authoritative. Temporary qualification workflows must not become an alternate release system.
