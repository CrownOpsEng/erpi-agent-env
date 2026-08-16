# Contributing

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

The full builder acceptance sequence is intentionally stronger than the lightweight source checks; see `VALIDATION.md`.
