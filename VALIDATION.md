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
- yq release checksum asset identity corrected so the builder verifies the exact `checksums` asset it downloads.

Node.js `24.19.0` Linux x64 and its pinned SHA-256 were rechecked against Node's signed release SHASUMS. `uv 0.12.5` and ripgrep `15.2.0` Linux assets were rechecked against their release metadata. Other native pins remain fail-closed because the builder verifies each downloaded artifact before extraction/install.

## Full acceptance sequence encoded in the builder

On an internet-connected Linux x86-64 glibc build host, `build.sh` must complete all of these before reporting success:

1. verify every direct native release artifact before extraction/use;
2. install the exact managed CPython version and record its resolved distribution ID;
3. create a `uv --relocatable` venv;
4. generate a hashed Python lock with the build cutoff;
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
