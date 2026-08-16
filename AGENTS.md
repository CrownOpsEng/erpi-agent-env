# Repository agent router

This repository owns the source and validation for the portable Magnet Agent Environment. It does not own Magnet Photos application dependencies or architecture.

Before changing builder/runtime source:

1. Read `README.md` and the directly affected files.
2. Preserve the fail-closed portability, integrity, credential-isolation, and offline-recovery boundaries already encoded by the tests.
3. Run `./tests/static-check.sh` after every source change.
4. For changes that can affect the hydrated payload, run `./build.sh` or the repository distribution workflow before release.
5. Never commit `dist/`, `.download-cache/`, credentials, or runtime-generated state.
6. Use the commit convention in `CONTRIBUTING.md`.

Keep this file short. Detailed behavior belongs in the code, tests, `README.md`, `BUILD-REVIEW.md`, and `VALIDATION.md`.
