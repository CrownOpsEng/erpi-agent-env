# Validation record

Date: 2026-08-15 (America/Toronto)  
Status: **builder/source validation complete; hydrated runtime validation pending first connected build**

## Reference evidence

The uploaded `J2911_venv_v2.zip` was extracted and inspected.

Useful mechanisms confirmed:

- bundled CPython runtime;
- location-aware Python launchers;
- `pyvenv.cfg` relocation repair;
- native executables beside the Python environment;
- capability/checksum manifests.

Relevant portability defect confirmed:

- at least one J2911 console script (`bin/opc`) retained the old absolute build path after relocation.

This is the reason the Magnet builder scans the entire shipped payload for the original build root rather than accepting a Python-only smoke test.

## Source/builder checks executed here

Passed:

- Bash syntax for builder, runtime shell scripts, and test scripts;
- POSIX-shell syntax for Python/Node/npm/npx launchers;
- Python compilation of `doctor.py`;
- required runtime/router source presence;
- compact-router size gate (`AGENTS.md` remains below 3 KB);
- native SHA-256 pin shape checks;
- source scan for accidental fixed `/mnt`, `/tmp`, `/home`, `/usr`, or `/opt` build-root assumptions;
- guard against redirecting `GH_CONFIG_DIR` into the portable payload;
- guard that ad-hoc UV Python installs and npm globals are routed to mutable `state/`;
- guard that immutable symlink verification excludes mutable `state/` consistently;
- GitHub authentication state-machine mock checks:
  - no credential -> status 2 and OAuth path permitted;
  - stored but unusable credential -> no blind OAuth replacement;
  - environment token override -> OAuth refused and test token not leaked;
  - successful mock OAuth -> API readiness verified;
- local `uv --relocatable` behavior experiments;
- local minimal repaired `pyvenv.cfg` semantics against CPython 3.13/uv, including correct `sys.prefix` and `uv pip check`;
- root-relative interpreter symlink behavior after relocation.

Current static command:

```bash
./tests/static-check.sh
```

returns green.

## Release-pin audit

Pins were reviewed against current upstream release information as of the audit date. Two draft defects were caught and corrected before first hydration:

- nonexistent CPython `3.13.15` -> `3.13.14`;
- yq verification simplified to the direct SHA-256 digest published for `yq_linux_amd64` in GitHub immutable release metadata; the multi-algorithm rhash checksum-table parser was removed.

Node.js `24.19.0` Linux x64 and its pinned SHA-256 were rechecked against Node's signed release SHASUMS. `uv 0.12.5` and ripgrep `15.2.0` Linux assets were rechecked against their release metadata. Other native pins remain fail-closed because the builder verifies each downloaded artifact before extraction/install.

## Full acceptance sequence encoded in the builder

On an internet-connected supported GNU/Linux x86-64 build host (kernel >= 4.18, glibc >= 2.28, Node-compatible libstdc++), `build.sh` must complete all of these before reporting success:

1. verify every direct native release artifact before extraction/use;
2. install the exact managed CPython version and record its resolved distribution ID;
3. create a `uv --relocatable` venv;
4. verify the source-frozen hashed Python lock (including its pinned lock-file SHA-256) without resolving versions during hydration;
5. create a wheel-only offline recovery set and sync from it;
6. repair relocation-sensitive Python metadata;
7. reject any remaining original build-root reference anywhere in the payload;
8. reject absolute symlinks in the shipped payload;
9. move the environment from a source path containing spaces to a deep path containing spaces and Unicode;
10. run the complete runtime self-test after relocation;
11. destroy the Python venv completely;
12. rebuild that venv with network-independent bundled artifacts only;
13. run the complete runtime self-test again;
14. scan again for original build-root residue;
15. emit immutable file hashes and immutable symlink topology (excluding declared mutable state and relocation metadata);
16. verify those manifests;
17. create the final TAR.GZ;
18. extract the archive into a new path;
19. self-test and integrity-verify the freshly extracted copy.

A failed gate terminates the build.

## Not falsely claimed as validated here

The current ChatGPT shell cannot download the third-party release payload because outbound shell DNS/network access is disabled. Therefore this record does **not** claim that the final hydrated runtime archive has already passed the encoded full acceptance sequence.

That proof occurs on the first connected Linux x86-64 build host by running:

```bash
./tests/static-check.sh
./build.sh
```

Expected artifacts:

```text
dist/magnet-agent-env-linux-x64-v1.0.0.tar.gz
dist/magnet-agent-env-linux-x64-v1.0.0.tar.gz.sha256
```

The freshly extracted runtime must then pass:

```bash
source magnet-agent-env/activate
agent-env doctor
agent-env selftest
agent-env verify
```

For a GitHub-dependent task, additionally run:

```bash
agent-env github
```

and invoke `agent-env github-auth` only when the status explicitly reports that no credential source exists.

## 2026-08-16 connected-host preflight correction

The first real build attempt on Ubuntu x86-64 with glibc 2.39 exposed a false-negative host check. The original probe used `ldd --version | head -1 | grep ...` while the builder enables `set -o pipefail`; an early-closing pipeline can report failure even when glibc is correctly present.

Corrected design:

- capture GNU tar version output before testing it;
- detect glibc primarily with `getconf GNU_LIBC_VERSION`;
- fall back to captured `ldd --version` output;
- never use an early-closing `head` pipeline for these host probes;
- static checks now reject reintroduction of the brittle pattern.

The corrected builder passed its static suite and was runtime-probed far enough to enter the uv download stage, proving that the Linux/x86-64/glibc preflight accepts the intended host class. Full hydrated validation remains pending the connected build.


### 2026-08-16 real hydration: yq checksum-table parser

The build progressed successfully through uv 0.12.5, CPython 3.13.14, creation and population of the relocatable Python environment and offline wheelhouse, Node.js 24.19.0, GitHub CLI 2.97.0, and jq 1.8.2. It then stopped before downloading yq because the builder incorrectly treated yq's multi-algorithm `rhash` `checksums` table as a two-column SHA-256 manifest.

The correction removes the checksum-table dependency entirely and pins `yq_linux_amd64` directly to GitHub's immutable v4.53.3 release-asset SHA-256 (`fa52a4e758c63d38299163fbdd1edfb4c4963247918bf9c1c5d31d84789eded4`). The same pass removed remaining `| head` pipelines from runtime scripts under `set -o pipefail` and made broken-symlink verification consistently ignore mutable `state/`.

### Live hydration portability-gate finding — 2026-08-16

A connected Ubuntu 24.04 / glibc 2.39 x86-64 hydration run successfully completed Python 3.13.14, the hashed wheelhouse and environment sync, Node 24.19.0, gh 2.97.0, jq 1.8.2, yq 4.53.3, ripgrep 15.2.0, actionlint 1.7.12, and gitleaks 8.30.1. The pre-relocation residue gate then correctly exposed three absolute-path locations: the uv-annotated requirements lock, uv-installed Python `_sysconfigdata_*.py`, and the deliberately mutable `env/pyvenv.cfg`.

The builder was revised to make the lock annotation-free, normalize uv's install-prefix sysconfig data into an immutable location-neutral form, and model `pyvenv.cfg` correctly as relocation metadata: permitted to name the current location before a move, repaired immediately after a move, and then included in stale-path rejection. The archive/extraction proof now also rejects any surviving reference to the archive-build location.


## FIXED4 approved implementation checks — 2026-08-16

After the second portability red-team, the builder was simplified and strengthened before another hydration attempt. Static/behavioral validation now additionally proves:

- the frozen 21-package lock matches every direct `requirements.in` pin, contains no prior build path/annotation, and matches the lock SHA-256 pinned in `versions.env`;
- uv builder/recovery isolation clears project/user Python artifact-selection overrides while preserving proxy and CA/system-certificate transport settings;
- `repair-python.sh` changes only the single `home` entry in `pyvenv.cfg`, preserves arbitrary uv metadata, is idempotent, and refuses to reconstruct a missing immutable `runtime/python/current` link;
- sysconfig normalization still survives a physical spaces/Unicode relocation;
- runtime self-test directly runs uv-generated `pytest` and `pip` console entrypoints and imports compiled `rpds` and PyYAML `CLoader`;
- supported runtime floor is recorded as Linux x86-64, kernel >= 4.18, glibc >= 2.28, with Node's `GLIBCXX_3.4.25` requirement; and
- the pip bootstrap wheel is exact-URL/SHA-256 pinned and verified before any pip code executes.

The next unresolved validation gate remains the only one that matters: a connected full `build.sh` run must reach relocation, offline venv destruction/rebuild, immutable-manifest verification, and fresh archive extraction without bypasses.

## FIXED5 connected-run findings — 2026-08-16

The FIXED4 connected run reused all directly downloaded native assets but re-downloaded uv-managed CPython because `UV_CACHE_DIR` had been placed in the disposable payload worktree. It then reached the absolute-symlink portability gate, which correctly rejected uv's managed-Python minor-version alias (`cpython-3.13-linux-x86_64-gnu`) because uv had created it as an absolute link to the exact `cpython-3.13.14-linux-x86_64-gnu` directory.

FIXED5 moves builder-only uv and managed-Python archive caches plus pip's download cache under `.download-cache/`. These caches are outside the output payload and survive failed/repeated builds. It also normalizes only top-level managed-Python absolute aliases whose targets stay inside the same managed-Python root to equivalent relative links; external absolute links fail closed. `tests/python-link-relocation-check.sh` behaviorally verifies the in-root rewrite and external-target refusal.
