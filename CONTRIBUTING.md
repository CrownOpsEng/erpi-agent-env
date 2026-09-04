# Contributing

## Change flow

Normal repository work uses a topic branch and pull request.

1. Start from the exact current `main` source.
2. Make semantic checkpoint commits as useful review/resumption boundaries emerge.
3. Keep each checkpoint internally coherent and independently truthful about what it verified.
4. Open/update one PR that synthesizes the final branch state rather than concatenating commit bodies.
5. Require **Validate** on the PR; use **Accept runtime** when the runtime itself needs full proof.
6. Integrate with a **squash merge** so `main` receives one coherent commit for the completed review unit.

Detailed branch commits remain available in the PR as cold historical evidence. The squash commit is the durable mainline record and follows the same semantic message contract.

Create an issue only when unresolved work needs a durable anchor independent of the active PR: an external report awaiting work, a deferred follow-up that genuinely matters, a decision requiring separate discussion, or a release blocker not being resolved here. Do not create issue ceremony around self-contained work already fully represented by its PR.

## Commit messages

Every new semantic checkpoint commit uses:

```text
type(scope): concise imperative summary

Why:
Why this checkpoint exists; identify the requirement, failure, invariant, or decision.

What:
What the final checkpoint changes and any important ownership consequences.

Verified:
Checks or observations actually completed for this checkpoint.

Impact:
Optional. Use when compatibility, persistence, security, packaging, or operations deserve explicit treatment.
```

Use a Conventional Commit type such as `feat`, `fix`, `perf`, `refactor`, `test`, `docs`, `ci`, or `chore`; keep the subject at most 72 characters. Mark actual breaking changes with `!` and a `BREAKING CHANGE:` footer when useful, but commit syntax never overrides real compatibility impact.

`Verified:` is evidence already obtained. Do not write future-tense claims such as “CI will pass” or use the commit body as a task list. Post-push/PR CI results belong in the PR/review evidence; the commit must remain truthful at creation time.

The record describes the final checkpoint, not the editing chronology. Preserve useful rationale; leave failed attempts and transient debugging narration in tool logs, review discussion, or other historical evidence when it matters.

## Pull requests

A PR is the coherent review unit. Use the repository template and synthesize:

- **Why** — the goal/problem/invariant;
- **What** — the final branch behavior/authority change;
- **Verified** — actual final-state evidence;
- **Compatibility** — exactly one of `Internal`, `Fix`, `Additive`, or `Breaking`;
- **Open / deferred** — only unresolved work that remains after this PR.

Do not paste every commit body into the PR. Higher-level records should compress lower-level evidence into coherent meaning.

### Compatibility classification

Classify by the supported environment contract, not by diff size or commit labels:

- **Internal** — no supported/public behavior changes.
- **Fix** — corrects supported behavior without incompatibility.
- **Additive** — adds a backward-compatible supported capability.
- **Breaking** — makes an existing supported behavior/interface incompatible.

Before `1.0.0`:

```text
Fix       → PATCH
Additive  → MINOR
Breaking  → MINOR
```

From `1.0.0` onward:

```text
Fix       → PATCH
Additive  → MINOR
Breaking  → MAJOR
```

`Internal` does not force a release by itself. The eventual release number follows the cumulative compatibility impact since the previous release, not the number of PRs or commits.

The supported contract includes documented `agent-env` commands/options and intentionally exported behavior, activation/relocation guarantees, documented offline/credential/security boundaries, artifact/manifest formats intentionally promised to consumers, and the supported runtime-host envelope. Private builder layout, helper implementation, temporary paths, test fixtures, and undocumented runtime internals are not compatibility promises.

## Product version and source identity

`PRODUCT_VERSION` in `versions.env` is the single product compatibility-version authority. It is ordinary SemVer or a real prerelease such as `0.2.0-rc.1`; **there is no `-dev` product version**.

Git owns exact source identity. Between release/prerelease tags, `PRODUCT_VERSION` remains the nearest released product identity and source state is described from Git ancestry using the nearest reachable version tag, commit distance, and abbreviated SHA.

Examples:

```text
exact stable release:
  product 0.1.1
  source  v0.1.1

ordinary development after it:
  product 0.1.1
  source  v0.1.1-17-g4c2fa17c9a1

exact release candidate:
  product 0.2.0-rc.1
  source  v0.2.0-rc.1

second development commit after that candidate:
  product 0.2.0-rc.1
  source  v0.2.0-rc.1-2-g91ab3c4d5e6f
```

The numeric distance makes development ordering visible; the Git SHA identifies the exact source; the tag identifies the compatibility state the development source descends from. Full source SHA remains in machine-readable provenance.

A development artifact therefore uses its source description directly:

```text
erpi-agent-env-linux-x64-v0.1.1-17-g4c2fa17c9a1.tar.gz
erpi-agent-env-linux-x64-v0.2.0-rc.1-2-g91ab3c4d5e6f.tar.gz
```

At an exact tag the same rule naturally produces the release/prerelease name:

```text
erpi-agent-env-linux-x64-v0.2.0-rc.1.tar.gz
erpi-agent-env-linux-x64-v0.2.0.tar.gz
```

Do not invent another build version or manually copy commit metadata into `versions.env`.

## Source identity and release lifecycle

A release/prerelease is a deliberate tagged compatibility state. Ordinary source commits do not change `PRODUCT_VERSION`.

Supported optional prerelease meanings are:

- `alpha.N` — intended target remains materially incomplete;
- `beta.N` — feature scope is substantially complete while compatibility/qualification still settles;
- `rc.N` — intended release scope/contract are frozen except release-blocking corrections;
- final — qualified normal release.

Do not manufacture stages that do not provide qualification value.

### Cutting a release or prerelease

The final state of a coherent PR may include its release/prerelease cut. The new `PRODUCT_VERSION` must move forward, and `.github/release-request.json` is updated to the same version in that review unit. This lets the normal squash merge integrate implementation and its release intent as one commit instead of requiring a ceremonial metadata-only PR. After integration, no later source range may continue under the new product version until the matching tag exists.

For example, a capability PR based on `v0.1.1` may finish with:

```text
PRODUCT_VERSION="0.2.0-rc.1"
.github/release-request.json → {"version":"0.2.0-rc.1"}
```

After squash integration, **Accept runtime** proves the exact mainline source—including both the implementation and version cut. Successful acceptance triggers the permanent publisher, which creates immutable tag:

```text
v0.2.0-rc.1
```

The exact tagged distribution is then built and accepted from that tag.

### Debugging a release candidate

If `0.2.0-rc.1` exposes a defect, **do not** change the product version back to a pseudo-development value and do not move/reuse the tag.

Commit the correction normally while `PRODUCT_VERSION` remains `0.2.0-rc.1`. Development artifacts naturally become:

```text
v0.2.0-rc.1-1-g0123456789ab
v0.2.0-rc.1-2-g123456789abc
```

When the source is again candidate-ready, make a release-metadata-only change to:

```text
0.2.0-rc.2
```

then tag/publish `v0.2.0-rc.2` after qualification. A defect in an unreleased `0.2.0` target therefore advances the RC number, not the patch number.

If qualification proves the intended compatibility target itself is wrong, choose a new truthful base version; for example `1.8.0-rc.1` may legitimately lead to `2.0.0-rc.1` when a breaking contract change is required.

### Finalizing

Finalization moves the accepted candidate to the final version, for example:

```text
0.2.0-rc.3 → 0.2.0
```

The final integrated source must receive full proof again because its bytes differ. No runtime behavior changes are permitted between the accepted final RC and final release; behavior changes require another candidate.

### Published immutability

Published stable releases and prereleases are immutable. Never move/reuse a version tag or replace assets after publication. The release workflow is tag-first/draft-first: establish the exact tag, prepare the draft, build/attach/verify all artifacts, then publish. Enable GitHub release immutability administratively when available.

## Validation

With a local checkout, run the smallest relevant checks while developing and every repository test script before proposing integration:

```bash
for test_script in tests/*.sh; do
  GIT_CONFIG_GLOBAL=/dev/null "$test_script"
done
```

Runtime/payload changes require complete pre-merge acceptance. When the local host has working Docker, run `./build.sh` locally on the clean, committed final PR head. When local Docker is unavailable, push the final PR head, manually dispatch **Accept runtime** with that exact 40-character SHA as `target_ref`, and require the run to succeed immediately before merge. Do not substitute fragmented checks or an older branch run.

The post-merge **Accept runtime** run on the exact `main` SHA remains the release gate even when local or PR-head acceptance already passed. This ensures the squash-integrated bytes, immutable tag, and published artifacts all share one accepted source identity.

Do not fragment a long-running gate merely to satisfy a wrapper timeout. Keep one logical process and give it adequate time or supervise/poll that same process.

A connector-only session must not claim local checks it did not run. Obtain a connector-backed Git handoff when coherent local Git semantics materially help; otherwise use the connected GitHub capability for remote state and rely only on evidence actually observed.

## Release automation

A coherent PR may update `PRODUCT_VERSION` and `.github/release-request.json` to the same intended stable/prerelease version alongside the implementation it releases. After squash integration, **Accept runtime** runs on the exact mainline commit. A successful mainline acceptance triggers `Publish release`, which verifies the release-cut record, creates/verifies immutable `v$PRODUCT_VERSION`, prepares/reuses a matching draft Release, and dispatches `Build distribution` against the real tag. Prerelease versions are published as GitHub prereleases.

`Build distribution` checks out the tag, verifies tag/SHA/product-version/source-description agreement, repeats the complete runtime build, writes `acceptance.json`, attaches archive/checksum/metadata to the draft, and only then publishes it.

Manual `Publish release` dispatch exists for idempotent recovery of an already accepted release source. `.github/release-request.json` contains only the requested version and is an auditable release command, not a second version authority.

Do not hand-maintain run IDs, hashes, source descriptions, or build chronology in current-state docs. Git, Actions evidence, release metadata, commits, and PRs own those records.
