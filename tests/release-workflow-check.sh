#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
PUBLISH="$ROOT/.github/workflows/publish-release.yml"
REPRO="$ROOT/.github/workflows/reproduce-distribution.yml"
ACCEPT="$ROOT/.github/workflows/accept-runtime.yml"
VALIDATE="$ROOT/.github/workflows/validate.yml"
REQUEST="$ROOT/.github/release-request.json"
README="$ROOT/README.md"
VALIDATION="$ROOT/VALIDATION.md"
AGENTS="$ROOT/AGENTS.md"
CONTRIBUTING="$ROOT/CONTRIBUTING.md"

for file in "$PUBLISH" "$REPRO" "$ACCEPT" "$VALIDATE" "$REQUEST" "$README" "$VALIDATION" "$AGENTS" "$CONTRIBUTING"; do
  [[ -s "$file" ]] || { echo "Required release/routing source missing: $file" >&2; exit 1; }
done
[[ ! -e "$ROOT/.github/workflows/build-dist.yml" ]] || { echo 'Legacy publication rebuild workflow must not remain.' >&2; exit 1; }

python3 - <<'PY' "$REQUEST"
import json, pathlib, re, sys
record=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
assert set(record)=={'version'},record
assert re.fullmatch(r'\d+\.\d+\.\d+(?:-(?:alpha|beta|rc)\.[1-9]\d*)?',record['version']),record
PY

# PRs are the normal review unit and their title/body are mechanically checked.
grep -F "github.event_name == 'pull_request'" "$VALIDATE" >/dev/null
grep -F 'scripts/check-pr-record.py --title "$PR_TITLE"' "$VALIDATE" >/dev/null
grep -F './tests/pr-record-check.sh' "$VALIDATE" >/dev/null
grep -F 'Normal repository work uses a topic branch and pull request.' "$CONTRIBUTING" >/dev/null
grep -F 'squash merge' "$CONTRIBUTING" >/dev/null
grep -F 'Development iterations after a published prerelease use an additional numeric revision' "$CONTRIBUTING" >/dev/null
grep -F 'Only after the candidate has passed the required real-world qualification' "$CONTRIBUTING" >/dev/null
grep -F 'does not require its own PR' "$CONTRIBUTING" >/dev/null
grep -F 'Corrections after a published prerelease use revisioned candidate builds' "$AGENTS" >/dev/null
grep -F 'manually dispatch **Accept runtime** with that exact 40-character SHA as `target_ref`' "$CONTRIBUTING" >/dev/null
grep -F 'target_ref:' "$ACCEPT" >/dev/null
grep -F 'ref: ${{ inputs.target_ref || github.sha }}' "$ACCEPT" >/dev/null
grep -F 'automatic post-merge run on the exact `main` SHA remains mandatory' "$VALIDATION" >/dev/null
grep -F 'run: ./build.sh' "$ACCEPT" >/dev/null
grep -F 'run: ./accept.sh' "$ACCEPT" >/dev/null
grep -F 'name: Retain exact accepted distribution' "$ACCEPT" >/dev/null
grep -F 'dist/*.tar.gz' "$ACCEPT" >/dev/null

# Successful main acceptance is the automatic release handoff; manual dispatch is recovery/idempotent.
grep -F 'workflow_run:' "$PUBLISH" >/dev/null
grep -F 'workflows: ["Accept runtime"]' "$PUBLISH" >/dev/null
grep -F "github.event.workflow_run.head_branch == 'main'" "$PUBLISH" >/dev/null
grep -F 'workflow_dispatch:' "$PUBLISH" >/dev/null
grep -F 'release-request.json' "$PUBLISH" >/dev/null
grep -F 'ordinary development from $base_tag; no release/prerelease will be published' "$PUBLISH" >/dev/null
grep -F 'candidate build $PRODUCT_VERSION from $base_tag; no release/prerelease will be published' "$PUBLISH" >/dev/null
grep -F 'Candidate build $PRODUCT_VERSION must leave release request at $base_version' "$PUBLISH" >/dev/null

# Publisher verifies and consumes exact acceptance evidence instead of rebuilding.
grep -F 'gh run download "$run_id"' "$PUBLISH" >/dev/null
grep -F 'acceptance-$TARGET_SHA' "$PUBLISH" >/dev/null
grep -F "'.source.commit'" "$PUBLISH" >/dev/null
grep -F "'.artifact.sha256'" "$PUBLISH" >/dev/null
grep -F 'sha256sum -c' "$PUBLISH" >/dev/null
! grep -F './build.sh' "$PUBLISH" >/dev/null
! grep -F 'gh workflow run' "$PUBLISH" >/dev/null

# Immutable tag/draft semantics remain intact and accepted bytes attach before publication.
grep -F 'git/ref/tags/$release_tag' "$PUBLISH" >/dev/null
grep -F 'ref=refs/tags/$release_tag' "$PUBLISH" >/dev/null
grep -F 'sha=$TARGET_SHA' "$PUBLISH" >/dev/null
grep -F 'Immutable tag $release_tag already points to' "$PUBLISH" >/dev/null
grep -F -- '--verify-tag' "$PUBLISH" >/dev/null
grep -F -- '--draft' "$PUBLISH" >/dev/null
grep -F 'args+=(--prerelease)' "$PUBLISH" >/dev/null
grep -F 'gh release upload "$RELEASE_TAG" "$ARCHIVE" "$SIDECAR" "$METADATA"' "$PUBLISH" >/dev/null
grep -F 'gh release edit "$RELEASE_TAG"' "$PUBLISH" >/dev/null

attach_line="$(grep -nF 'gh release upload "$RELEASE_TAG"' "$PUBLISH" | cut -d: -f1)"
publish_line="$(grep -nF 'gh release edit "$RELEASE_TAG"' "$PUBLISH" | tail -1 | cut -d: -f1)"
[[ -n "$attach_line" && -n "$publish_line" && "$attach_line" -lt "$publish_line" ]] || {
  echo 'Accepted assets must attach before the draft is published.' >&2
  exit 1
}

# Independent reproduction is audit-only and never mutates a Release.
grep -F 'name: Reproduce distribution' "$REPRO" >/dev/null
grep -F 'required: true' "$REPRO" >/dev/null
grep -F 'run: ./build.sh' "$REPRO" >/dev/null
grep -F 'run: ./accept.sh' "$REPRO" >/dev/null
grep -F -- '--release-tag "$RELEASE_TAG"' "$REPRO" >/dev/null
! grep -F 'gh release upload' "$REPRO" >/dev/null
! grep -F 'gh release edit' "$REPRO" >/dev/null

# Current-state authority remains version-neutral and routes rather than duplicating procedure.
! grep -F 'v1.0.0' "$README"
grep -F '**Publish release**' "$README" >/dev/null
grep -F 'Change, commit, version, and release policy: `CONTRIBUTING.md`.' "$AGENTS" >/dev/null
if grep -F '.github/release-request.json' "$AGENTS" >/dev/null; then
  echo 'Root AGENTS.md should route release policy, not duplicate release-command procedure.' >&2
  exit 1
fi
if grep -R -nE 'PRODUCT_VERSION="[^"]*-dev|BUNDLE_VERSION="[^"]*-dev' "$ROOT" --exclude-dir=.git --exclude='commit-range-check.sh' --exclude='build-identity-check.sh' --exclude='version-transition-check.sh'; then
  echo 'Live source must not reintroduce pseudo-development product versions.' >&2
  exit 1
fi

for retired in 'BUILD-REVIEW.md' 'docs/validation-history.md'; do
  if grep -nF "$retired" "$README" "$VALIDATION" "$AGENTS" "$CONTRIBUTING"; then
    echo "Live authority docs reference retired history ledger: $retired" >&2
    exit 1
  fi
done
[[ ! -e "$ROOT/BUILD-REVIEW.md" ]] || { echo 'Retired BUILD-REVIEW.md must not return to the live tree.' >&2; exit 1; }
[[ ! -e "$ROOT/docs/validation-history.md" ]] || { echo 'Retired docs/validation-history.md must not return to the live tree.' >&2; exit 1; }

echo "Release workflow and AI-routing checks passed."
