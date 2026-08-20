# Validation contract

This file defines the stable validation authority for Magnet Agent Environment. Git history records changes; GitHub Actions and release assets record execution/publication evidence. Do not maintain a second hand-written run ledger here.

## Source validation

`./tests/static-check.sh` is the fast source gate. It must fail closed on malformed scripts, inconsistent pins/locks, missing required source, unsafe credential handling, router bloat, invalid portability assumptions, mismatched source-controlled qualified native payloads, malformed provenance metadata, incomplete required direct-license material, and unsafe Node-capsule filesystem/ownership behavior.

Source validation does not prove the runtime.

## Runtime acceptance

A payload-affecting source commit is releasable only after **Accept runtime** builds the complete archive from that exact commit and the resulting runtime passes all builder gates, including:

- verified upstream/custom payload hashes before execution or inclusion
- supported Linux x86-64/glibc host contract
- exact managed-Python build provenance plus Python relocation repair, native-import checks, and offline venv destruction/rebuild
- bundled command functional probes, including ShellCheck positive/negative behavior, Miller transformation, and HTTPX CLI localhost execution
- exact-lock offline Node capsule hydration using the real bundled packages, content-bound ownership, import execution, and safe cleanup
- source-level Node-capsule negative tests for lock mismatch, all-or-nothing late conflicts, symlinked `node_modules`/scope escape attempts, stale ownership, pre-existing repository packages, and legacy-marker refusal
- PostgreSQL server/client version and extension integration checks
- disposable PostgreSQL start/query, pgTAP positive/negative accounting, plpgsql_check, dump/restore, `pg_amcheck`, pgbench, and stopped-cluster checksum verification when the acceptance host is unprivileged
- PostgreSQL child-exit propagation and signal-interrupted teardown with no orphaned cluster state or occupied loopback port
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

The PostgreSQL server is not accepted from a prebuilt third-party binary bundle. Every full runtime build fetches the exact pinned official PostgreSQL source tarball, verifies its SHA-256, and builds the normal install prefix inside a digest-pinned manylinux 2.28 image. Optional readline, zlib, and ICU integrations are disabled to avoid unnecessary external runtime-library dependencies; the resulting ELF symbol floor and dynamic dependencies are checked before runtime acceptance.

The source-controlled PostgreSQL client and plpgsql_check payloads remain qualified build inputs. Their pinned hashes are validated by source checks and by `build.sh` before extraction. Their existing promotion baseline is a controlled GLIBC 2.28 build from pinned PostgreSQL 17.10/plpgsql_check sources; qualified maximum GLIBC requirements were 2.25 for the client payload and 2.17 for plpgsql_check. `scripts/rebuild-qualified-database-assets.sh` retains their pinned maintainer reproduction path.

Any future server source, configure, build-image, client, or extension-native change requires full source validation and runtime acceptance. A harness defect is fixed and the complete relevant qualification is rerun; partial progress is not promoted as success.

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

## Project promotion proof

A generic environment capability is not proven useful to Magnet Photos merely because its standalone self-test passes. Database-capability releases must additionally be exercised against the target repository's current authoritative migrations/tests before the environment release is published when that project is the motivating consumer.

That project proof should use the repository's real pinned client dependency and existing suites unchanged wherever possible. The environment must not carry project schema, business logic, roles, migrations, or test expectations solely to manufacture a passing result.

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
