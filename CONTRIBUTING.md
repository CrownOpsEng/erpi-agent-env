# Contributing

## Change flow

This repository is intentionally direct-to-`main`. It is a small, single-purpose builder repository with immediate automated validation, so mandatory pull requests would add ceremony without creating a meaningful approval boundary.

Use one coherent commit per change when practical and inspect the resulting GitHub Actions runs after pushing. Pull requests remain available when explicit review, temporary isolation, or multi-contributor coordination is useful; they are not the default path. Optional PRs receive lightweight **Validate** coverage and the same detailed commit-history policy as direct pushes.

Payload-affecting pushes to `main` automatically run the full **Accept runtime** build. Distribution publishing remains separate.

## Commit messages

The commit history is part of this repository's engineering record. A terse Conventional Commit subject is **not enough**.

Every new commit—whether pushed directly to `main` or introduced through a PR—must use this structure:

```text
type(scope): imperative summary

Why:
Explain the problem, decision, failure mode, or reason this change exists.

What:
Explain the material implementation and behavior/authority that changed.

Validation:
State the evidence available at commit time: local checks that ran, or the exact post-push CI proof that is required. Do not claim a check passed before it actually ran.
```

The subject must be at most 72 characters and use a Conventional Commit type. Preferred types are `feat`, `fix`, `perf`, `refactor`, `test`, `docs`, `ci`, and `chore`. Use a focused lowercase scope such as `builder`, `runtime`, `python`, `github`, `dist`, `ci`, `repo`, `release`, or `validation`.

The body is not filler. `Why:`, `What:`, and `Validation:` must each contain useful detail. **Validate** checks every commit newly introduced by a direct push and every commit in the PR range, not only the current tip. A PR with one terse intermediate commit therefore fails even if its latest commit is detailed. If using a PR, keep its commits compliant as you work or squash/rebase before asking for merge.

Example:

```text
fix(runtime): preserve Git auth across bundle relocation

Why:
GitHub CLI can configure Git with an absolute path to its current executable, which breaks after moving this portable bundle.

What:
Use a repo-local location-neutral `!gh auth git-credential` helper and verify the authenticated push path without changing the remote.

Validation:
Behavioral transport tests cover helper setup, bundle relocation, absence of global credential mutation, and a no-write push dry run; post-push Validate and Accept runtime are required.
```

Mark breaking changes with `!` and a `BREAKING CHANGE:` footer when applicable. Do not rewrite already-published history solely to improve older commit messages; enforce the stronger standard forward from the current history.

## Validation

When a shell checkout is available, run:

```bash
./tests/static-check.sh
```

For changes that may alter the produced runtime or its portability/integrity behavior, `./build.sh` is useful locally when practical.

A connector-only agent may not have a usable shell checkout. In that case it must not claim local validation: make the coherent direct-to-`main` commit, inspect **Validate**, and for payload-affecting changes require **Accept runtime** to succeed. GitHub Actions is an intentional supported acceptance host, not a fallback of last resort.

Do **not** manually refresh candidate hashes, run IDs, versions, or per-run chronology in tracked narrative files. `VALIDATION.md` defines the stable validation contract; successful **Accept runtime** runs upload `acceptance.json` evidence for the exact commit, and published Releases carry their runtime archive, checksum, and `acceptance.json`. Git history preserves why/what/validation for changes, and GitHub Actions preserves execution history. Superseded historical documents should be removed from the live tree once they no longer serve current operation or authority—their content remains recoverable from Git.

## Releases

`BUNDLE_VERSION` in `versions.env` is the source version. Release candidates use SemVer prerelease identities such as `0.2.0-rc.1` and are not published through the stable release workflow. Stable release tags are exactly `v$BUNDLE_VERSION`.

Candidate flow:

1. set `BUNDLE_VERSION` to `x.y.z-rc.N`;
2. pass source validation and **Accept runtime** for that exact candidate source;
3. inspect/test the produced candidate archive directly;
4. repair and increment the RC number as needed;
5. only after approval, change the source version to stable `x.y.z` and accept the exact final commit again.

Normal stable release flow:

1. change `BUNDLE_VERSION` from the accepted candidate identity to the intended stable version on `main`;
2. require that exact commit's **Validate** and **Accept runtime** runs to succeed;
3. invoke permanent **Publish release** for that exact accepted source;
4. **Publish release** verifies acceptance, creates/verifies the exact lightweight Git tag, and creates/reuses only a matching **draft** Release;
5. it dispatches **Build distribution** for that tag;
6. **Build distribution** checks out the real tag, verifies it matches the source/version and a mutable draft, repeats the complete acceptance build, uploads the archive/checksum/`acceptance.json` to the draft, then publishes the Release.

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

If a release build fails after the draft was prepared, the tag remains pinned to the accepted source and the draft remains recoverable. Correct the pipeline on `main`, accept the intended release source, retarget the request if the release source itself changed, then rerun the permanent publisher. Distribution assets may be replaced only while the Release is still draft; publication happens only after all release assets are attached successfully.

**Build distribution** can also be run without a release tag to produce a short-lived Actions artifact without publishing anything.

The explicit workflow dispatch from **Publish release** to **Build distribution** is intentional. GitHub suppresses most follow-on events caused by actions performed with `GITHUB_TOKEN`, while `workflow_dispatch` is explicitly allowed to start another workflow.

### Release immutability

The release pipeline is intentionally tag-first/draft-first so GitHub release immutability can be enabled safely. All assets are attached while the Release is draft and publication is the final action.

Recommended repository setting for future releases when available: **Settings → General → Releases → Enable release immutability**. This setting is administrative and is not changed by the build workflows themselves.

Pre-1.0 versions are appropriate while the environment accumulates real-world usage evidence. `1.0.0` should signal a deliberately proven/stable compatibility contract, not merely a working package.

## Development and release version lifecycle

Version identifiers describe lifecycle state; commits and artifact hashes describe exact bytes.

- **Development:** keep `BUNDLE_VERSION` at `X.Y.Z-dev` while payload, validation, or release work is still changing or any known blocker remains. The exact identity of a development snapshot is the pair `(BUNDLE_VERSION, source commit)` and may be written for humans as `X.Y.Z-dev+g<short-commit-sha>`. The `+g...` form is derived metadata; never hand-maintain it in `versions.env`.
- **Release candidate:** use `X.Y.Z-rc.N` only after the development source has no known release blockers and the strongest inexpensive/targeted checks have passed. Cutting an RC is a deliberate version-only promotion whenever practical. An RC identifies one immutable source commit; never modify code while retaining that RC identity.
- **Rejected candidate:** if an RC exposes a defect, reject it, make the next development commit return `BUNDLE_VERSION` to `X.Y.Z-dev`, fix and validate normally, and never reuse the rejected RC number. Cut the next `rc.N` only when the branch is again believed releasable.
- **Stable:** use `X.Y.Z` only after the candidate has passed the required direct artifact and motivating-project promotion proofs. The stable version change is deliberate and the exact stable commit must be accepted again because version bytes are part of the payload.
- **Build metadata:** SemVer `+...` metadata is for derived snapshot identification, not readiness or precedence. Do not append metadata to an RC as a way to keep changing its source.

Normal pull-request commits are development checkpoints. Run the inexpensive source gate locally before pushing; PR CI should provide lightweight `Validate` feedback. Use full `Accept runtime` deliberately when runtime proof is warranted, for a candidate, or automatically on the documented main-branch path. Do not use release-candidate numbering or full clean builds as an inner debugging loop.
