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

A release-metadata-only promotion is deliberately terse because it is not a review unit and carries no new behavior. After the commit-range checker proves that only `versions.env` and `.github/release-request.json` changed, and that the version transition is a valid clean release/prerelease promotion, its complete commit message is exactly:

```text
chore(release): promote v<version>
```

No body is required for that mechanically bounded exception. A release-shaped subject never relaxes the detailed-message requirement for any commit that changes other files.

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

`PRODUCT_VERSION` in `versions.env` is the product/build SemVer authority.

Published compatibility states use ordinary SemVer or a deliberate prerelease such as `0.2.0-rc.1`. Development iterations after a published prerelease use an additional numeric revision on that same line, for example `0.2.0-rc.1-1`, `0.2.0-rc.1-2`, and so on. These revisioned versions are build identities, not release candidates and not Git tags.

Git remains the exact source authority. The nearest reachable immutable `v<release-version>` tag, first-parent distance, and exact SHA are recorded separately so two source states can never be confused merely because their product/build version is similar.

Examples:

```text
exact stable release:
  product 0.1.1
  source  v0.1.1

ordinary development after stable:
  product 0.1.1
  source  v0.1.1-17-g4c2fa17c9a1

exact release candidate:
  product 0.2.0-rc.1
  source  v0.2.0-rc.1

first corrected build after that candidate:
  product 0.2.0-rc.1-1
  source  v0.2.0-rc.1-1-g0123456789ab
```

The revision suffix answers "which candidate build is this?"; Git provenance answers "which exact source produced it?". Do not use `-dev` or pretend an unverified correction is a new RC.

## Source identity and release lifecycle

A release/prerelease is a deliberate, verified, immutable tagged compatibility state. A candidate-build revision is ordinary development and must never trigger tag/release publication.

Supported optional prerelease meanings are:

- `alpha.N` — intended target remains materially incomplete;
- `beta.N` — feature scope is substantially complete while compatibility/qualification still settles;
- `rc.N` — intended release scope/contract are frozen except release-blocking corrections;
- final — qualified normal release.

Do not manufacture stages that do not provide qualification value.

### Candidate builds after a prerelease

If `0.2.0-rc.1` exposes a defect, keep tag `v0.2.0-rc.1` immutable and advance the build revision while correcting it:

```text
0.2.0-rc.1-1
0.2.0-rc.1-2
```

The revision change may accompany the source correction it identifies. `.github/release-request.json` stays at the last published prerelease (`0.2.0-rc.1` here), so normal acceptance of `rc.1-1` or `rc.1-2` cannot accidentally publish a release.

Run source validation, runtime acceptance, and motivating-consumer proof on the revisioned build. Real-world qualification may iterate through as many candidate builds as necessary. **Do not cut `rc.2` merely because `rc.1` needed a fix.**

### Promoting a verified release or prerelease

Only after the candidate has passed the required real-world qualification should the next immutable release/prerelease be cut. Promotion is a **release-metadata-only** source change: set `PRODUCT_VERSION` to the clean release version and update `.github/release-request.json` to the same value. The release cut is not a separate review unit and **does not require its own PR**; it may be the final metadata-only checkpoint in an already-active change range or a direct metadata-only promotion after the qualified candidate has been integrated, subject to repository branch permissions.

For example, after `0.2.0-rc.1-3` is actually proven ready for promotion:

```text
PRODUCT_VERSION="0.2.0-rc.2"
.github/release-request.json → {"version":"0.2.0-rc.2"}
```

After squash integration, **Accept runtime** builds and qualifies that exact promotion commit and retains the accepted archive, checksum, and machine-generated acceptance metadata. The permanent publisher may then create immutable tag `v0.2.0-rc.2` at the accepted SHA and publish those exact accepted bytes after the release checks complete.

A clean `alpha.N`, `beta.N`, `rc.N`, or final version is therefore a release assertion. A revisioned form such as `rc.1-4` is explicitly not one.

If qualification proves the intended compatibility target itself is wrong, choose a new truthful base version. Do not increment PATCH merely because an unreleased target needed another candidate build.

### Finalizing

Finalization changes only approved release metadata from the accepted candidate line to the final version, for example:

```text
0.2.0-rc.3-2 → 0.2.0
```

The final promotion receives full proof again. No runtime behavior change is smuggled into the promotion commit; behavior changes go through another revisioned candidate build first.

### Published immutability

Published stable releases and prereleases are immutable. Never move/reuse a version tag or replace assets after publication. The release workflow is tag-first/draft-first: establish the exact tag, prepare the draft, verify and attach the exact already-accepted artifacts, then publish. Enable GitHub release immutability administratively when available.

## Validation

With a local checkout, run the smallest relevant checks while developing and every repository test script before proposing integration:

```bash
for test_script in tests/*.sh; do
  GIT_CONFIG_GLOBAL=/dev/null "$test_script"
done
```

Runtime/payload changes require complete pre-merge acceptance. When local build prerequisites are available, run `./build.sh` on the clean, committed final PR head and then run `./accept.sh` against the produced archive. `build.sh` constructs the artifact; `accept.sh` owns the expensive behavioral, relocation, offline-recovery, and reproducibility proofs. A verified warm PostgreSQL derived-cache hit does not require Docker; a cold miss does. If the local builder cannot complete, push the final PR head, manually dispatch **Accept runtime** with that exact 40-character SHA as `target_ref`, and require the run to succeed immediately before merge. Do not substitute fragmented checks or an older branch run.

The post-merge **Accept runtime** run on the exact `main` SHA remains the release gate even when local or PR-head acceptance already passed. This ensures the squash-integrated bytes, immutable tag, and published artifacts all share one accepted source identity.

Do not fragment a long-running gate merely to satisfy a wrapper timeout. Keep one logical process and give it adequate time or supervise/poll that same process.

A connector-only session must not claim local checks it did not run. Obtain a connector-backed Git handoff when coherent local Git semantics materially help; otherwise use the connected GitHub capability for remote state and rely only on evidence actually observed.

## Release automation

Revisioned candidate builds leave `.github/release-request.json` at the last published prerelease; `Publish release` must classify them as development and exit without tagging or publishing. Once qualification earns promotion, a metadata-only release cut updates `PRODUCT_VERSION` and `.github/release-request.json` to the same clean stable/prerelease version. That cut does not require a dedicated PR. After the promotion reaches `main`, **Accept runtime** builds and qualifies the exact mainline source, writes `acceptance.json`, and retains the accepted archive/checksum/metadata as workflow evidence.

A successful mainline acceptance triggers `Publish release`. Publication verifies that exact successful acceptance run and retained artifact, creates/verifies immutable `v$PRODUCT_VERSION` at the accepted SHA, attaches the already-accepted bytes to the matching draft Release, and publishes without rebuilding them. Prerelease versions are published as GitHub prereleases.

**Reproduce distribution** remains available as an explicit manual audit path. It checks out an existing immutable release/prerelease tag, independently rebuilds and accepts it, and uploads reproduction evidence only. It does not attach or publish release assets and is not part of the normal release path.

Manual `Publish release` dispatch exists for idempotent recovery of an already accepted release source. `.github/release-request.json` contains only the requested version and is an auditable release command, not a second version authority.

Do not hand-maintain run IDs, hashes, source descriptions, or build chronology in current-state docs. Git, Actions evidence, release metadata, commits, and PRs own those records.
