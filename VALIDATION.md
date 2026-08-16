# Validation record

Date: 2026-08-15 (America/Toronto)

## Evidence inspected

The uploaded `J2911_venv_v2.zip` was extracted and inspected as a reference implementation.

Observed useful mechanisms:

- bundled CPython runtime;
- location-aware Python launchers;
- `pyvenv.cfg` repair after relocation;
- native executables exposed beside the Python environment;
- environment/capability manifests and checksum checking.

Observed defect relevant to this design:

- the J2911 archive retained its old build path in at least one installed console script (`bin/opc`), even though the wrapped Python launcher worked after relocation.

This is why the Magnet builder has a whole-tree original-build-root residue gate rather than treating a successful Python launch as sufficient portability proof.

## Validation completed in this sandbox

- builder shell syntax checked for all shell templates;
- Python `doctor.py` compiled successfully;
- pinned native SHA-256 values validated for correct hash shape;
- required builder/runtime source files checked present and non-empty;
- source tree scanned for accidental `/mnt`, `/tmp`, `/home`, `/usr` or `/opt` build-path assumptions beyond portable interpreter shebangs;
- builder `--help` executed successfully;
- TAR.GZ builder handoff archive created, extracted to a fresh directory and static checks rerun successfully;
- ZIP builder handoff archive created, extracted to a fresh directory and static checks rerun successfully;
- a local relocation experiment confirmed that a root-relative interpreter symlink behind a launcher preserves venv `sys.prefix` after moving the tree when `pyvenv.cfg` is repaired.

## Validation not executable in this sandbox

The shell execution environment used to construct this handoff has outbound DNS/download access disabled. Therefore the final third-party payload could not be hydrated here from upstream release assets.

This is an execution-environment limitation, not hidden as a successful test. The builder is designed to perform the following acceptance tests automatically on an internet-connected Linux x86-64 glibc build host:

1. SHA-256 verification of every downloaded native artifact.
2. Exact Python dependency resolution with generated hashes.
3. Wheel-only offline recovery set creation.
4. Initial runtime self-test.
5. Whole-tree rejection of the original build root.
6. Rejection of absolute symlinks.
7. Relocation from a build path containing spaces to a deep path containing spaces and Unicode.
8. Complete runtime self-test after relocation.
9. Destruction and full offline recreation of the Python venv.
10. Runtime self-test after offline recreation.
11. Second old-build-root residue scan after recreation.
12. Immutable-file and symlink-topology manifest generation and verification.
13. TAR.GZ creation.
14. Fresh archive extraction followed by self-test and integrity verification.

A build is not reported successful unless all of those gates pass.

## Acceptance command

On a suitable build host:

```bash
./tests/static-check.sh
./build.sh
```

The expected final artifacts are:

```text
dist/magnet-agent-env-linux-x64-v1.0.0.tar.gz
dist/magnet-agent-env-linux-x64-v1.0.0.tar.gz.sha256
```

The extracted runtime should then pass:

```bash
source magnet-agent-env/activate
agent-env doctor
agent-env selftest
agent-env verify
```
