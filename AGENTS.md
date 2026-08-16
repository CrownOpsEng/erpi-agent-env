# Repository agent router

This repository owns the source and validation for the portable Magnet Agent Environment. It does not own Magnet Photos application dependencies or architecture.

Before changing builder/runtime source:

1. Read `README.md` and the directly affected files.
2. Preserve the fail-closed portability, integrity, credential-isolation, and offline-recovery boundaries already encoded by the tests.
3. Run `./tests/static-check.sh` after every source change.
4. For changes that can affect the hydrated payload, run `./build.sh` or rely on the repository runtime-acceptance workflow before release.
5. Never commit `dist/`, `.download-cache/`, credentials, or runtime-generated state.
6. Use the commit convention in `CONTRIBUTING.md`.
7. The default change flow is direct to `main`. Do not create a pull request unless the user explicitly asks for review or isolation; make coherent commits and inspect the resulting CI instead.
8. Do not manually copy current candidate versions, run IDs, or artifact hashes into `VALIDATION.md`. CI-generated `acceptance.json` evidence is authoritative for accepted builds; GitHub Release assets are authoritative for published builds. Update `VALIDATION.md` only if that authority/validation contract itself changes.
9. To publish, update `BUNDLE_VERSION`, require that exact source commit to pass **Accept runtime**, then use the permanent **Publish release** workflow. If workflow dispatch is unavailable but repository writes are available, create/update `.github/release-request.json` with the exact accepted commit SHA and version; that file is the durable connector-trigger for the same publisher. Do not invent another tag/release path.

Keep this file short. Detailed behavior belongs in the code, tests, `README.md`, `BUILD-REVIEW.md`, `CONTRIBUTING.md`, and `VALIDATION.md`.
