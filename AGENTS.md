# ERPI Agent Environment source router

## Scope

This file governs the **builder/source repository only**. It is not shipped in the runtime bundle.

The bundle's consumer agent contract is source-controlled as `payload/AGENTS.md.in` and rendered to the bundle root as `AGENTS.md`. Keep that source under a non-`AGENTS.md` filename here: nested `AGENTS.md` files are agent instruction surfaces, so a shipped router must not accidentally become scoped instructions for maintaining the builder.

## Authority map

- Builder purpose, payload, portability, and source architecture: `README.md`.
- Change, commit, version, and release policy: `CONTRIBUTING.md`.
- Validation and acceptance contract: `VALIDATION.md`.
- Consumer agent routing: `payload/AGENTS.md.in`.
- Consumer operating reference: `templates/RUNTIME-README.md`.
- Exact versions, integrity pins, and product version: `versions.env`.
- Executable truth: `build.sh`, `scripts/`, `tests/`, and `.github/workflows/`.

Read only the authority needed for the current concern. If surfaces disagree, treat that as drift rather than silently choosing one.

## Working rules

- Preserve the fail-closed portability, integrity, credential-isolation, offline-recovery, and host-capability boundaries already encoded by executable checks.
- Keep builder policy and consumer operation separate. Consumer files describe how to use an extracted bundle; builder files describe how to construct, validate, and release it. Do not copy build/release procedure into the consumer router.
- Keep durable target-state files neutral and present-tense. Put chronology, rejected alternatives, and prior states in commits, pull requests, issues, Actions evidence, or explicit provenance records.
- Normal changes use a topic branch and PR, with semantic checkpoint commits and squash integration; `CONTRIBUTING.md` owns the detailed record, compatibility, version, and release rules.
- If no usable shell checkout exists, do not claim local validation. Use the connector-backed Git handoff when coherent local Git semantics matter; otherwise keep remote operations in the connected GitHub capability and report only observed proof.
- Preserve one logical long-running validation. Give it an adequate outer timeout or supervise/poll that same process; do not fragment a suite merely to satisfy an agent wrapper timeout.
- Before merge, run `./build.sh` followed by `./accept.sh` when local build prerequisites are available; construction alone is not acceptance. A verified warm PostgreSQL derived-cache hit does not require Docker, while a cold cache miss does. If the local builder cannot complete, dispatch **Accept runtime** against the exact final PR-head SHA and require that run to pass immediately before merge; the post-merge main acceptance remains the release gate.
- Product/build versions use SemVer. Published stable/prerelease tags are immutable release assertions. Corrections after a published prerelease use revisioned candidate builds such as `0.3.0-rc.1-1`; they are development/qualification builds and never trigger tags or releases. Promote to a new clean RC only after required real-world qualification, using a release-metadata-only change. A release cut is not a review unit and does not require its own PR. Git ancestry remains exact source identity; never use pseudo-development SemVer.
- Never commit `dist/`, `.download-cache/`, credentials, runtime-generated mutable state, or manual copies of CI/release evidence.

Keep this router small. Put detailed policy in its owner and objective rules in executable checks.
