# Magnet Agent Environment — design audit and red-team record

Status: **FIXED4 design approved; pending complete hydrated acceptance run**  
Audit date: 2026-08-15 (America/Toronto)

## Decision

The environment is justified, but only as a small external capability layer for agents. It must not become a second application stack, a parallel Magnet Photos toolchain, or an agent framework.

The retained design is intentionally asymmetric: a modest portable payload removes recurring execution blockers (`gh`, the correct Node major, structured-data/search/security tools, and dependable Python), while project-specific behavior remains owned by the target repository.

## Architecture that survives review

- External to Magnet Photos and its dependency model.
- Supported GNU/Linux x86-64 first: kernel >= 4.18, glibc >= 2.28, and Node's GLIBCXX_3.4.25 host-runtime floor; no false claim of cross-OS/cross-architecture/musl portability.
- Short root `AGENTS.md` router; detailed material is loaded only on demand.
- `agent-env` is the small executable command surface.
- Magnet Photos still owns Supabase/PGLS versions and database operations through `package.json`, `package-lock.json`, and `Makefile`.
- Credentials are host/session state, never payload state.
- Verified payload is stable; ad-hoc UV/npm tools, extra managed Pythons, caches, and bytecode go under mutable `state/`.
- Bundled CPython is retained for completeness/recovery, but Python is not introduced as Magnet application architecture.

## Red-team findings corrected

### 1. J2911 was not comprehensively relocatable

The uploaded J2911 environment successfully relocated for its wrapped Python path, but at least one installed console script (`bin/opc`) retained the original absolute build root. A successful `python` smoke test is therefore insufficient portability proof.

**Correction:** Magnet uses `uv venv --relocatable`, repairs the small remaining base-interpreter metadata boundary, rejects absolute symlinks, and scans the whole payload for the original build root before and after relocation/offline rebuild.

### 2. Draft Python pin was impossible

The first draft specified CPython `3.13.15`, which did not exist at the audit date. Python `3.13.14` is the current 3.13 maintenance release available to the intended managed-Python source.

**Correction:** pin changed to `3.13.14` and all documentation aligned.

### 3. yq checksum asset identity was briefly mismatched

The builder downloads the release asset named `checksums`. Its SHA-256 is different from `checksums-bsd.bundle`; using the latter digest would fail a legitimate build.

**Correction:** the pin now verifies the exact `checksums` asset first, then resolves and verifies the `yq_linux_amd64` digest from that trusted list.

### 4. GitHub auth was too eager

An early draft allowed `github-auth` to start OAuth after any failed GitHub readiness check, including an existing credential with a network/API problem.

**Correction:** OAuth is initiated automatically only when no credential source exists. Environment-token override, stored-but-unusable credentials, and valid auth are distinct states. A local mock state-machine test enforces this behavior and checks that an environment token is never echoed.

### 5. Generic `doctor` mixed local diagnostics with network/auth state

Running GitHub authentication checks on every diagnostic invocation adds latency, side effects, and unnecessary dependency on network state.

**Correction:** `agent-env doctor` is local. `agent-env github` is the explicit demand-driven readiness check used at the start of a GitHub-dependent turn.

### 6. Mutable install paths could have contaminated the verified payload

An early draft pointed ad-hoc UV Python installs at the bundled Python directory. npm global installs also needed an explicit non-payload home.

**Correction:** extra UV Pythons, UV tools, npm globals, caches, and Python bytecode are redirected to `state/`.

### 7. Mutable state was inconsistently excluded from integrity topology

File hashes excluded `state/`, but symlink verification originally did not. A legitimate ad-hoc UV/npm tool could therefore make an otherwise healthy bundle fail verification.

**Correction:** mutable state is excluded consistently from immutable hashes and symlink topology. Portability checks still cover the shipped immutable payload.

### 8. Copying the managed Python executable was unsafe

Some standalone Python distributions use executable-relative (`$ORIGIN`) library lookup. Copying the ELF into `env/bin` can break that relationship.

**Correction:** the venv uses a relative `.python-real` symlink back into the bundled managed-Python tree, behind a self-repairing launcher.

### 9. Archive reproducibility was overclaimed

GNU tar ownership normalization does not by itself make a gzip archive bit-for-bit reproducible.

**Correction:** the builder no longer describes this as deterministic/reproducible archive metadata. The actual guarantees are integrity, relocation, offline reconstruction, and archive-extraction proof.

## GitHub authentication policy

For a turn that may need GitHub, the router requires `agent-env github` before substantial dependent work. If no credential exists and the user is engaged, `agent-env github-auth` starts the normal browser/device OAuth flow immediately, verifies API access, and the agent resumes the original task.

The environment does **not** pre-request extra OAuth scopes. Additional scopes are requested only after a concrete operation proves they are needed. Git credential-helper setup is also separate because it mutates host Git configuration.

## Deliberate omissions

These were considered and rejected for v1 because they do not earn their cost yet:

- Supabase CLI or Postgres language server: Magnet already pins them.
- `psql` or raw database convenience commands: they create a path around Magnet's safe Make targets.
- Docker client: a client binary cannot provide the daemon/socket/kernel capability agents actually need.
- Git and Make: ordinary host prerequisites; bundling them creates disproportionate native dependency complexity.
- `fd`, `tree`, `rich`, `ruff`, `requests`, `sqlite3` CLI, pandoc, document-production tools: existing primitives cover current needs; promote only after an observed repeated need.
- MCP/agent framework/orchestration layer: no demonstrated need.
- Portable credentials: unacceptable security tradeoff.

## Remaining honest limitations

- The payload cannot create network access, credentials, Docker daemon access, filesystem execute permission, or kernel capabilities denied by the host sandbox.
- Supported GNU/Linux x86-64 portability is not Windows/macOS/ARM/musl portability; those would be separate builds if ever justified.
- GitHub OAuth persistence depends on the host credential/config environment. On hosts without a credential store, GitHub CLI may fall back to its normal plaintext config behavior; credentials still remain outside the portable payload.
- The final hydrated third-party runtime has not been built inside this ChatGPT shell because outbound download/DNS is unavailable here. The builder fails closed and runs the full acceptance sequence on the connected build host.

## Acceptance threshold

Do not call a hydrated v1 bundle accepted unless `build.sh` completes every native checksum, relocation, offline Python destruction/rebuild, old-build-path scan, immutable verification, and fresh archive-extraction proof without bypasses.

## Hydration red-team findings — 2026-08-16

The first live hydration run reached the portability gate and surfaced three absolute-path residues rather than packaging them:

- `manifest/requirements.lock` contained uv annotation comments naming the absolute input requirements path;
- `env/pyvenv.cfg` correctly contained the current absolute base-Python location, but the pre-move gate had incorrectly begun treating that declared mutable relocation metadata as immutable residue;
- uv-managed python-build-standalone `_sysconfigdata_*.py` contained the Python installation prefix. This is expected from uv's install-time sysconfig patching, but it would become stale after moving the complete Python installation.

Corrections are deliberately narrow: freeze the already-resolved annotation-free 21-package lock as builder input; exclude only `pyvenv.cfg` from the pre-move stale-root scan and require it clean after repair; normalize the installed Python prefix inside `_sysconfigdata_*.py` to a location-neutral sentinel resolved from that module's current location at import time. The normalized sysconfig file remains immutable and checksum-covered. Runtime self-test proves `BINDIR` and `LIBDIR` resolve to the relocated bundled Python root, and fresh archive extraction must contain no reference to the archive-build location.


## FIXED4 foundational portability audit — 2026-08-16

The architecture was re-audited against current uv 0.12.5 source, python-build-standalone behavior, the working J2911 implementation, uv's still-open interpreter-bundling/export gap, and the live hydration failures. The result reduced custom authority rather than adding machinery.

- `uv venv --relocatable` remains the native owner of standard console/gui entrypoint and activation portability. Current uv still links a Unix venv to an external/base interpreter and writes an absolute `home`, so a bundled-moving-interpreter bridge is genuinely outside the native guarantee.
- The J2911 self-location/`pyvenv.cfg` repair pattern is retained, but repair now changes **only `home`** and preserves all uv-generated metadata. Missing `runtime/python/current` is immutable-topology corruption and fails closed instead of being recreated.
- uv's python-build-standalone sysconfig install-prefix patch becomes stale only because this bundle subsequently moves the complete managed-Python install. The existing narrow location-derived sysconfig normalization remains the smallest robust correction and stays checksum-covered.
- The Python dependency lock is frozen into builder v1 and SHA-256 pinned. Hydration no longer resolves dependency versions.
- uv build/recovery commands ignore ambient project/user config and Python artifact-selection overrides while preserving proxy/CA transport settings.
- pip's temporary bootstrap wheel is exact-URL and SHA-256 verified before execution.
- Relocation self-tests now directly exercise uv-generated `pip`/`pytest` scripts and compiled `rpds`/PyYAML code, covering the stale-console-script and native-extension failure classes.
- The runtime contract is explicit: GNU/Linux x86-64, kernel >= 4.18, glibc >= 2.28, and a Node-compatible libstdc++ exposing GLIBCXX_3.4.25.

Rejected again: direct `uv pip --system` installation (would make relocatable package entrypoints our problem), conda/conda-pack, generic relocators, runtime-Python reconstruction, and broader custom repair frameworks. One narrow metadata repair plus uv's native relocation remains the higher-leverage design.

## FIXED5 cache/topology correction — 2026-08-16

The first FIXED4 connected run showed two narrow issues before relocation:

- uv's managed-Python download cache was incorrectly located under the disposable build payload, so every new build downloaded CPython again even though direct native assets reused `.download-cache`;
- uv created its normal top-level minor-version managed-Python alias as an absolute symlink to the exact patch-version directory, which correctly failed the bundle's absolute-symlink gate.

Corrections remain native/minimal. Build-time `UV_CACHE_DIR`, `UV_PYTHON_CACHE_DIR`, and pip cache now live under the builder's existing `.download-cache/` and are never shipped. uv therefore remains responsible for fetching and hash-validating its managed Python, but repeat builds can reuse the cached archive. The managed-Python convenience alias is preserved, not deleted: if an absolute top-level link resolves inside the same managed-Python root it is rewritten to the equivalent relative target; an external absolute target fails closed. A synthetic behavioral test proves both cases.
