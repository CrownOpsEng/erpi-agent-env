# Contributing

## Change flow

This repository is intentionally direct-to-`main`. It is a small, single-purpose builder repository with immediate automated validation, so mandatory pull requests would add ceremony without creating a meaningful approval boundary.

Use one coherent commit per change when practical and inspect the resulting GitHub Actions runs after pushing. Pull requests remain available when explicit review, temporary isolation, or multi-contributor coordination is useful; they are not the default path. Optional PRs receive lightweight **Validate** coverage.

Payload-affecting pushes to `main` automatically run the full **Accept runtime** build. Distribution publishing remains separate.

## Commit messages

Use Conventional Commits:

```text
type(scope): imperative summary
```

Preferred types: `feat`, `fix`, `perf`, `refactor`, `test`, `docs`, `ci`, `chore`.

Preferred scopes: `builder`, `runtime`, `python`, `github`, `dist`, `ci`, `repo`.

Use the body when the reason, failure mode, or tradeoff is not obvious from the diff. Mark breaking changes with `!` and a `BREAKING CHANGE:` footer when applicable.

## Validation

When a shell checkout is available, run:

```bash
./tests/static-check.sh
```

For changes that may alter the produced runtime or its portability/integrity behavior, `./build.sh` is useful locally when practical.

A connector-only agent may not have a usable shell checkout. In that case it must not claim local validation: make the coherent direct-to-`main` commit, inspect **Validate**, and for payload-affecting changes require **Accept runtime** to succeed. GitHub Actions is an intentional supported acceptance host, not a fallback of last resort.

Do **not** manually refresh candidate hashes, run IDs, or versions in `VALIDATION.md`. That file defines the stable validation authority/contract. Successful **Accept runtime** runs upload a small `acceptance.json` plus SHA sidecar for the exact commit; published Releases carry their own runtime archive, checksum and `acceptance.json`. Historical chronology is under `docs/validation-history.md`.

## Releases

`BUNDLE_VERSION` in `versions.env` is the source version. Release tags are exactly `v$BUNDLE_VERSION`.

Normal release flow:

1. change `BUNDLE_VERSION` on `main` as part of the intended release source;
2. require that exact commit's **Validate** and **Accept runtime** runs to succeed;
3. invoke permanent **Publish release** for that exact accepted source;
4. **Publish release** verifies acceptance and creates/reuses only a matching **draft** Release/tag;
5. it dispatches **Build distribution** for that tag;
6. **Build distribution** checks out the tag, repeats the complete acceptance build, uploads the archive/checksum/`acceptance.json` to the draft, then publishes the Release.

There are two durable ways to invoke **Publish release**:

- **GitHub UI / workflow-dispatch capable client:** run **Publish release** and provide the accepted `target_ref`.
- **Connector-only agent session:** create or update `.github/release-request.json` on `main` with the exact already-accepted commit SHA and version:

```json
{
  "version": "0.2.0",
  "target_sha": "0123456789abcdef0123456789abcdef01234567"
}
```

Changing that request file triggers the same permanent publisher. The workflow requires an exact 40-character lowercase commit SHA, verifies its `BUNDLE_VERSION`, and refuses to publish unless that commit already has a successful **Accept runtime** result. The request file is an auditable release command, not version authority; `versions.env` remains authoritative.

If a release build fails after the draft was prepared, the draft is intentionally recoverable: rerun **Build distribution** with its `release_tag`. The build may replace partial assets while the Release is still draft, but publication happens only after all release assets are attached successfully.

**Build distribution** can also be run without a release tag to produce a short-lived Actions artifact without publishing anything.

The explicit workflow dispatch from **Publish release** to **Build distribution** is intentional. GitHub suppresses most follow-on events caused by actions performed with `GITHUB_TOKEN`, while `workflow_dispatch` is explicitly allowed to start another workflow.

### Release immutability

The release pipeline is intentionally draft-first so GitHub release immutability can be enabled safely. GitHub recommends attaching all assets to a draft and publishing only afterward; once immutability is enabled, future published release tags/assets are locked and GitHub creates a release attestation.

Recommended repository setting for future releases: **Settings → General → Releases → Enable release immutability**. This setting is administrative and is not changed by the build workflows themselves. It applies to future releases, so the initial `v0.1.0` release remains historical even if the setting is enabled afterward.

Pre-1.0 versions are appropriate while the environment accumulates real-world usage evidence. `1.0.0` should signal a deliberately proven/stable compatibility contract, not merely a working package.
