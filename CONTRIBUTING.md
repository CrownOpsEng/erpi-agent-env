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

A payload-affecting direct push to `main` runs that full acceptance sequence automatically in CI, so local hydration is optional when the GitHub runner is the intended proof. The full builder acceptance sequence is intentionally stronger than the lightweight source checks; see `VALIDATION.md`.
