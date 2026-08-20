# Validation contract

This file defines the stable validation authority for Magnet Agent Environment. Git history records changes; GitHub Actions and release assets record execution/publication evidence. Do not maintain a second hand-written run ledger here.

## Source validation

`./tests/static-check.sh` is the fast source gate. It must fail closed on malformed scripts, inconsistent pins/locks, missing required source, unsafe credential handling, router bloat, invalid portability assumptions, and mismatched source-controlled qualified native payloads.

Source validation does not prove the runtime.

## Runtime acceptance

A payload-affecting source commit is releasable only after **Accept runtime** builds the complete archive from that exact commit and the resulting runtime passes all builder gates, including:

- verified upstream/custom payload hashes before execution or inclusion
- supported Linux x86-64/glibc host contract
- Python relocation repair, native-import checks, and offline venv destruction/rebuild
- bundled command functional probes, including ShellCheck positive/negative behavior, Miller transformation, and HTTPX CLI startup
- PostgreSQL server/client version and extension integration checks
- disposable PostgreSQL start/query/pgTAP/plpgsql_check smoke when the acceptance host is unprivileged
- hostile relocation with spaces/unicode/deep paths
- PostgreSQL lifecycle under that hostile relocation path over explicit `127.0.0.1` TCP with Unix-domain sockets disabled, preventing relocation depth from becoming a socket-path failure mode
- rejection of original build-root residue and absolute symlinks
- pristine mutable state before packaging
- immutable checksum/symlink manifest verification
- fresh archive extraction, repair, self-test, and stale-path rejection

The accepted archive hash and exact source SHA belong in machine-generated `acceptance.json` and the archive sidecar, not copied into narrative docs.

## PostgreSQL native-input qualification

The source-controlled PostgreSQL client and plpgsql_check payloads are qualified build inputs, not opaque trust shortcuts. Their pinned hashes are validated by source checks and by `build.sh` before extraction.

Their promotion baseline was a controlled GLIBC 2.28 build from pinned PostgreSQL 17.10 and plpgsql_check upstream sources, integrated with the pinned Zonky PostgreSQL 17.10 server and pgTAP 1.3.3, then exercised through hostile relocation, psql/extension execution, concurrent pgbench load, dump/restore, `pg_amcheck`, and stopped-cluster `pg_checksums`. Qualified maximum GLIBC requirements were 2.25 for the client payload and 2.17 for the plpgsql_check native payload.

Future native-payload changes require equivalent or stronger fail-closed qualification before their hashes may replace the pins. A harness defect is fixed and the complete qualification rerun from source; partial progress is not promoted as success.
`scripts/rebuild-qualified-database-assets.sh` retains the pinned maintainer rebuild path for the source-controlled native payloads. It requires Docker and is deliberately separate from ordinary lightweight hydration; successful reproduction must match the pinned payload hashes exactly.

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

A release requires:

1. source commit passes source validation;
2. the exact payload-affecting source commit passes **Accept runtime**;
3. release version is updated intentionally;
4. permanent release workflow verifies the accepted source/tag relationship;
5. **Build distribution** rebuilds and accepts the tagged distribution before publication;
6. release assets include the archive, SHA-256 sidecar, and `acceptance.json`.

No manual tag/upload path is authoritative. Temporary qualification workflows must not become an alternate release system.
