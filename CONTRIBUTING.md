# Contributing

## Change flow

This repository is intentionally direct-to-`main`. It is a small, single-purpose builder repository with immediate automated validation, so mandatory pull requests would add ceremony without creating a meaningful approval boundary.

Use one coherent commit per change when practical and inspect the resulting GitHub Actions runs after pushing. Pull requests remain available when explicit review, temporary isolation, or multi-contributor coordination is useful; they are not the default path.

Payload-affecting pushes to `main` automatically run the full runtime acceptance build. Distribution publishing remains separate.

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

`BUNDLE_VERSION` in `versions.env` is the source version. Release tags are exactly `v$BUNDLE_VERSION`.

Normal release flow:

1. change `BUNDLE_VERSION` on `main` as part of the intended release source;
2. require that exact commit's **Validate** and **Accept runtime** workflows to succeed;
3. run the permanent **Publish release** workflow, normally with `target_ref=main` (or an explicit already-accepted commit/ref when needed);
4. **Publish release** verifies the target acceptance result, creates the matching GitHub Release/tag, and explicitly dispatches **Build distribution**; and
5. **Build distribution** checks out the release tag, re-runs the complete acceptance build, then attaches the runtime archive, checksum sidecar, and `acceptance.json` to the Release.

The explicit dispatch in step 4 is intentional: GitHub suppresses most follow-on workflow events caused by actions performed with `GITHUB_TOKEN`, so an Actions-created Release cannot rely on its own `release: published` event to start another workflow. The release trigger remains supported for Releases published directly through GitHub's UI/API by a user.

**Build distribution** can also be run manually without a release tag to produce a short-lived Actions artifact, or with an existing `release_tag` to rebuild/attach that release.

Pre-1.0 versions are appropriate while the environment is still accumulating real-world usage evidence. A `1.0.0` tag should signal a deliberately proven/stable compatibility contract rather than merely the first working package.
