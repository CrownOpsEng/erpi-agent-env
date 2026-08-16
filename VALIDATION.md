# Validation record

Date: 2026-08-16 (America/Edmonton)  
Status: **accepted release candidate: source validation, connected hydration, relocation, deterministic offline recovery, immutable verification, and GitHub CI runtime acceptance complete; v1.0.0 is not yet tagged or published**

## Validation philosophy

This environment is accepted by behavior, not by a successful Python launch or a plausible archive layout. A releasable build must prove that the complete payload survives relocation, that its Python environment can be destroyed and reconstructed without network access, and that reconstruction restores the checksum-covered canonical environment rather than merely producing something operationally similar.

The builder therefore fails closed on stale build roots, absolute symlinks, unexpected managed-Python install metadata, dependency drift, corrupted or unverified native assets, and integrity mismatches.

## J2911 reference evidence

The uploaded `J2911_venv_v2.zip` was extracted and inspected as a working reference implementation.

Useful mechanisms confirmed:

- bundled CPython runtime;
- location-aware Python launchers;
- `pyvenv.cfg` relocation repair;
- native executables beside the Python environment; and
- capability/checksum manifests.

A relevant portability defect was also confirmed: at least one installed console script (`bin/opc`) retained its old absolute build path after relocation. That finding is why Magnet scans the complete shipped payload for former build roots and directly exercises installed console entrypoints rather than treating a Python-only smoke test as sufficient evidence.

## Static and behavioral source checks

The current `./tests/static-check.sh` suite validates, among other things:

- Bash/POSIX-shell syntax for builder, runtime wrappers, and tests;
- Python compilation of helper scripts;
- required runtime/router source presence and compact router size;
- exact native SHA-256 pin shapes and the frozen Python lock SHA-256;
- consistency between `requirements.in` and the 21-package hashed lock;
- absence of temporary build paths and uv resolver annotations from the frozen lock;
- credential isolation (`GH_CONFIG_DIR` is never redirected into the bundle);
- mutable-state routing for ad-hoc uv/Python/npm activity;
- correct immutable-verification exclusions for declared runtime state;
- GitHub authentication state-machine behavior;
- uv build/recovery isolation from ambient artifact-selection overrides;
- `pyvenv.cfg` repair semantics and fail-closed immutable Python topology;
- managed-Python convenience-link relocation;
- managed-Python sysconfig relocation through spaces/Unicode paths;
- direct execution of uv-generated `pip` and `pytest` entrypoints;
- imports of compiled Python extensions (`rpds`, PyYAML `CLoader`);
- rejection of brittle early-closing `| head` pipelines under `pipefail`; and
- deterministic removal of uv's optional timestamp-bearing `uv_cache.json` metadata before immutable verification.

## Release-pin audit

Pins were reviewed against upstream release information during construction. Important corrections included:

- nonexistent CPython `3.13.15` -> `3.13.14`;
- yq verification changed from an incorrect multi-algorithm `rhash` table parser to the direct immutable v4.53.3 `yq_linux_amd64` SHA-256;
- Node.js 24.19.0 Linux x64 and its runtime floor were checked against Node's release/build metadata; and
- the pip bootstrap wheel is fetched from its exact PyPI wheel URL and SHA-256 verified before any pip code executes.

The v1 runtime contract is Linux x86-64 with kernel >= 4.18, glibc >= 2.28, and libstdc++ exposing `GLIBCXX_3.4.25`.

## Full acceptance sequence encoded in `build.sh`

On a supported connected GNU/Linux x86-64 host, `build.sh` must complete all of the following before reporting success:

1. verify direct native release artifacts before extraction/use;
2. install the exact uv-managed CPython version and record its distribution ID;
3. normalize managed-Python internal convenience links without allowing external absolute targets;
4. create a native `uv venv --relocatable` environment;
5. verify the source-frozen hashed Python lock without resolving dependency versions during hydration;
6. construct a wheel-only offline recovery set and synchronize from it;
7. normalize uv-managed Python sysconfig into a location-derived immutable form;
8. canonicalize nonfunctional uv installer-cache metadata in the venv;
9. reject original build-root residue and absolute symlinks;
10. relocate to a deep path containing spaces and Unicode;
11. run the full runtime self-test, including compiled extensions and console entrypoints;
12. destroy the Python venv completely;
13. rebuild it using network-independent bundled artifacts only;
14. canonicalize the rebuilt venv and verify it against the immutable contract;
15. re-scan for former build roots;
16. reset mutable `state/` to its pristine distribution shape;
17. emit and verify immutable file hashes and symlink topology;
18. create the final TAR.GZ and sidecar checksum;
19. extract into a fresh location; and
20. self-test, stale-path-scan, and integrity-verify the freshly extracted copy.

Any failed gate terminates the build.

## Connected-host correction timeline

### Host preflight

The first Ubuntu x86-64 / glibc 2.39 run exposed a false-negative glibc check caused by `ldd --version | head -1 | grep ...` under `set -o pipefail`. The builder now captures version output, prefers `getconf GNU_LIBC_VERSION`, falls back to captured `ldd` output, and statically rejects reintroduction of early-closing `head` pipelines.

### yq release verification

The next connected run progressed through Python, Node, GitHub CLI, and jq before exposing the incorrect assumption that yq's `checksums` file was a two-column SHA-256 manifest. The parser was removed; the exact yq release binary digest is pinned directly.

### Python install-prefix residue

A later pre-relocation gate correctly caught three path-bearing sources: uv lock annotations, managed-Python `_sysconfigdata_*.py`, and the deliberately location-sensitive `env/pyvenv.cfg`.

The lock became annotation-free, sysconfig was normalized into a location-derived immutable form, and `pyvenv.cfg` was modeled as the sole relocation-mutable venv file: valid at the current location, repaired after a move, then included in stale-path rejection.

### FIXED4 red-team simplification

The second portability audit retained uv's native `--relocatable` behavior rather than replacing it with a custom environment format. The J2911-style repair bridge was narrowed to `pyvenv.cfg home`; immutable Python topology fails closed; builder uv invocations are isolated from ambient selection configuration; native/compiled Python and uv-generated entrypoints are tested directly; and the 21-package hashed lock became source-controlled input.

### FIXED5 cache and managed-Python link correction

The next run showed that uv-managed CPython downloads were being cached inside a disposable worktree and that uv had created a top-level absolute minor-version convenience link. Builder-only uv/Python/pip caches were moved under persistent `.download-cache/`, and in-root managed-Python aliases are now normalized to equivalent relative links while external absolute targets fail closed.

### FIXED6 distribution-state correction

FIXED5 passed relocation and complete offline Python destruction/rebuild. Its remaining archive proof failure consisted entirely of path-bearing bytecode/cache files under declared mutable `state/`. FIXED6 established a distribution-boundary invariant: after all behavioral proofs, mutable state is removed and recreated empty before immutable manifests and archive creation. The fresh extraction scan remains strict after first-use self-test.

## Pre-canonicalization v1.0.0 candidate

FIXED6 then completed the full connected acceptance sequence and produced:

```text
magnet-agent-env-linux-x64-v1.0.0.tar.gz
SHA-256: ddd3f395b7da087d6cc62cca102af05d67a9199a1bc9fc588fd2410bb77e444e
Size: 154M
```

That artifact was independently checked for traversal-safe archive paths, internal-only relative symlinks, empty initial mutable state, relocation to a deep spaces/Unicode path, `agent-env selftest`, `agent-env verify`, and `agent-env doctor --json`.

A deeper post-build recovery test then found one integrity-model defect: `agent-env rebuild-python` recreated a fully working venv offline, but immutable verification reported exactly 42 differences. They were the 21 distributions' `*.dist-info/uv_cache.json` files and the corresponding 21 `RECORD` files. uv's optional cache metadata contains the installation timestamp, so a later rebuild was semantically identical but not byte-stable.

The `ddd3f395...` artifact is therefore retained as successful historical FIXED6 evidence but is **superseded as the v1.0.0 release candidate**.

## Deterministic offline-rebuild correction

The recovery fix preserves the strong integrity boundary rather than excluding `env/` from verification. Runtime canonicalization now removes each optional `*.dist-info/uv_cache.json` and the exact corresponding row from that distribution's `RECORD` before immutable verification. `RECORD` does not hash itself, so package content hashes remain intact.

An independent original-vs-offline-rebuilt comparison demonstrated zero differences across checksum-covered venv files after this canonicalization. The shipped `rebuild-python` flow already invokes self-test/canonicalization before `verify`, so the fix required no new recovery subsystem or manifest exception.

## GitHub direct-to-main acceptance — 2026-08-16

The repository now uses a deliberately small direct-to-`main` automation model:

- **Validate**: lightweight source/static checks on every `main` push;
- **Accept runtime**: a full non-publishing build on payload-affecting `main` changes only; and
- **Build distribution**: manual or GitHub-Release-triggered full build that uploads the archive/checksum and, for a published Release, attaches them to that Release.

The first `Accept runtime` run after deterministic recovery was a cold-cache GitHub-hosted Ubuntu 24.04 build. It downloaded all required artifacts, passed relocation, complete offline venv destruction/rebuild, immutable verification, fresh extraction, and `Build complete`, then seeded approximately 130 MiB of persistent builder cache. Run `31939149120` completed successfully.

The second run, against commit `c3312735abc5430f6af1c2676e70fcf3bf260b7b`, restored that cache and again passed the full sequence. Run `31939286736` / job `95146012682` completed successfully in under one minute. The canonical v1.0.0 release-candidate artifact produced by that run is:

```text
magnet-agent-env-linux-x64-v1.0.0.tar.gz
SHA-256: 5da38faed7287908e5094b20aafdd53d158c11d324bda23984756f71017d18ea
Size: 154M
```

The warm run showed cache hits for uv, the managed-Python archive, the verified pip bootstrap wheel, Python wheels, Node, gh, jq, yq, ripgrep, actionlint, and gitleaks. CPython still performs a clean extraction/install into the disposable build root, preserving the relocation proof without re-downloading the archive.

The same commit's lightweight **Validate** workflow also completed successfully.

## Release state

At the time of this record there is intentionally **no Git tag and no GitHub Release**. The source/runtime candidate is accepted, but v1.0.0 has not yet been published.

The release workflow requires the published Release tag to equal `v$BUNDLE_VERSION`, repeats the complete acceptance build, prints the resulting digest to the Actions log and Step Summary, uploads the archive/checksum as a short-lived Actions artifact, and attaches both files to the GitHub Release.

This keeps acceptance evidence separate from publication: a direct-to-main change can be tested immediately, while an actual release is produced only by an explicit release event or manual distribution run.
