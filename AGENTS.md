# Magnet Agent Environment source router

## Scope

This file governs the **builder/source repository only**. It is not shipped in the runtime bundle.

The bundle's consumer agent contract is source-controlled as `payload/AGENTS.md.in` and rendered to the bundle root as `AGENTS.md`. Keep that source under a non-`AGENTS.md` filename here: nested `AGENTS.md` files are agent instruction surfaces, so a shipped router must not accidentally become scoped instructions for maintaining the builder.

## Authority map

- Builder purpose, payload, portability, and source architecture: `README.md`.
- Change, commit, version, and release policy: `CONTRIBUTING.md`.
- Validation and acceptance contract: `VALIDATION.md`.
- Consumer agent routing: `payload/AGENTS.md.in`.
- Consumer operating reference: `templates/RUNTIME-README.md`.
- Exact versions, integrity pins, and lifecycle version: `versions.env`.
- Executable truth: `build.sh`, `scripts/`, `tests/`, and `.github/workflows/`.

Read only the authority needed for the current concern. If surfaces disagree, treat that as drift rather than silently choosing one.

## Working rules

- Preserve the fail-closed portability, integrity, credential-isolation, offline-recovery, and host-capability boundaries already encoded by executable checks.
- Keep builder policy and consumer operation separate. Consumer files describe how to use an extracted bundle; builder files describe how to construct, validate, and release it. Do not copy build/release procedure into the consumer router.
- Keep durable target-state files neutral and present-tense. Put chronology, rejected alternatives, and prior states in commits, pull requests, issues, Actions evidence, or explicit provenance records.
- The repository is intentionally direct-to-`main`; use a pull request only when explicit review, isolation, or coordination earns it. Make one coherent commit per logical change when practical.
- Every new commit follows the detailed record contract in `CONTRIBUTING.md`.
- If no usable shell checkout exists, do not claim local validation. Make the coherent repository change through the connected GitHub capability and inspect **Validate**. Payload-affecting changes additionally require **Accept runtime** before a release candidate can be cut.
- Preserve one logical long-running validation. Give it an adequate outer timeout or supervise/poll that same process; do not fragment a suite merely to satisfy an agent wrapper timeout.
- A release-candidate identity is immutable. If source must change after `X.Y.Z-rc.N`, the next source commit returns to `X.Y.Z-dev`; never modify code or documentation while retaining the rejected RC identity.
- Never commit `dist/`, `.download-cache/`, credentials, runtime-generated mutable state, or manual copies of CI/release evidence.

Keep this router small. Put detailed policy in its owner and objective rules in executable checks.
