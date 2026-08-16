# Repository agent router

This repository owns the source, validation, and release automation for the portable Magnet Agent Environment. It does not own Magnet Photos application dependencies or architecture.

Before changing builder/runtime source:

1. Read `README.md` and the directly affected files.
2. Preserve the fail-closed portability, integrity, credential-isolation, offline-recovery, and host-capability boundaries already encoded by the tests.
3. If a shell checkout is available, run `./tests/static-check.sh` after source changes. In a connector-only session, make one coherent direct-to-`main` commit and inspect the resulting **Validate** run instead; do not pretend a local check ran.
4. For payload-affecting changes, require the resulting **Accept runtime** run to pass before release. A local `./build.sh` is useful when available but is not required when GitHub Actions is the intended acceptance host.
5. Never commit `dist/`, `.download-cache/`, credentials, runtime-generated state, or manual copies of CI/release evidence.
6. Every new commit must follow the detailed commit contract in `CONTRIBUTING.md`: Conventional Commit subject plus substantive `Why:`, `What:`, and `Validation:` sections. **Validate** checks every commit introduced by a direct push and every commit in an optional PR, not only the tip. Preserve published history; do not rewrite old commits merely to improve their messages.
7. The default change flow is direct to `main`. Do not create a pull request unless the user explicitly asks for review or isolation; make coherent commits and inspect resulting CI. Optional PRs receive the same detailed-history check plus lightweight source validation.
8. `VALIDATION.md` defines the stable validation authority/contract. CI-generated `acceptance.json`, GitHub Actions runs/artifacts, Git tags, and GitHub Release assets are the evidence. Do not manually copy current candidate versions, run IDs, hashes, or execution chronology into tracked narrative files.
9. To publish, update `BUNDLE_VERSION`, require that exact source commit to pass **Accept runtime**, then use the permanent **Publish release** workflow. If workflow dispatch is unavailable but repository writes are available, create/update `.github/release-request.json` with the exact accepted commit SHA and version; that is the durable connector trigger. The publisher creates/verifies the exact release tag, prepares/reuses only a draft Release, and **Build distribution** attaches accepted assets before publication. Do not invent another tag/release path.
10. Remove superseded operational/audit documents once their current authority is gone. Git history and Actions already preserve the record; the live tree should contain only material that still helps operate, validate, build, or understand the current system.

Keep this file short. Current operational authority belongs in `README.md`, `CONTRIBUTING.md`, and `VALIDATION.md`. Git history is the change narrative; GitHub Actions is the execution narrative; Releases are publication evidence. Do not maintain a second manual history ledger.
