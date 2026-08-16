# Contributing

## Change flow

This repository is intentionally direct-to-`main`. It is a small, single-purpose builder repository with immediate automated validation, so mandatory pull requests would add ceremony without creating a meaningful approval boundary.

Use one coherent commit per change when practical and inspect the resulting GitHub Actions runs after pushing. Pull requests remain available when explicit review, temporary isolation, or multi-contributor coordination is useful; they are not the default path.

Payload-affecting pushes to `main` automatically run the full runtime acceptance build. Distribution publishing remains separate and happens through the **Build distribution** workflow manually or when a GitHub Release is published.

## Commit messages

Use Conventional Commits:

```text
type(scope): imperative summary
```

Preferred types: `feat`, `fix`, `perf`, `refactor`, `test`, `docs`, `ci`, `chore`.

Preferred scopes: `builder`, `runtime`, `python`, `github`, `dist`, `ci`, `repo`.

Examples:

```text
feat(builder): add portable agent environment builder
fix(python): normalize relocatable sysconfig metadata
perf(builder): persist managed Python download cache
ci(dist): build portable runtime on demand
```

Keep the subject concise and describe one coherent change. Use the body when the reason, failure mode, or tradeoff is not obvious from the diff. Mark breaking changes with `!` and a `BREAKING CHANGE:` footer when applicable.

## Validation

For every source change:

```bash
./tests/static-check.sh
```

For changes that may alter the produced runtime or its portability/integrity behavior, also run:

```bash
./build.sh
```

A payload-affecting direct push to `main` runs that full acceptance sequence automatically in CI, so local hydration is optional when the GitHub runner is the intended proof.

**Do not manually refresh candidate hashes, run IDs, or versions in `VALIDATION.md`.** That file defines the stable validation authority and contract. Every successful **Accept runtime** run automatically uploads a tiny `acceptance.json` plus the archive SHA-256 sidecar as the current machine-readable evidence for that commit. Published Releases carry their own runtime archive, checksum, and `acceptance.json` and are authoritative for published state. The historical engineering chronology lives under `docs/validation-history.md`.

## Releases

`BUNDLE_VERSION` in `versions.env` is the source version. Release tags must be exactly `v$BUNDLE_VERSION`; the distribution workflow rejects a mismatch.

Before publishing a release, make the intended version change on `main` and require its normal **Validate** and **Accept runtime** runs to succeed. Publishing the matching GitHub Release then triggers a fresh, independent **Build distribution** run from the tag and attaches the accepted archive, checksum sidecar, and `acceptance.json` to the Release.

Pre-1.0 versions are appropriate while the environment is still accumulating real-world usage evidence. A `1.0.0` tag should signal a deliberately proven/stable compatibility contract rather than merely the first working package.
