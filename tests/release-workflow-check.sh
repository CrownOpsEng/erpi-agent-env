#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
PUBLISH="$ROOT/.github/workflows/publish-release.yml"
BUILD="$ROOT/.github/workflows/build-dist.yml"
README="$ROOT/README.md"
VALIDATION="$ROOT/VALIDATION.md"
AGENTS="$ROOT/AGENTS.md"
CONTRIBUTING="$ROOT/CONTRIBUTING.md"

for file in "$PUBLISH" "$BUILD" "$README" "$VALIDATION" "$AGENTS" "$CONTRIBUTING"; do
  [[ -s "$file" ]] || { echo "Required release-routing source missing: $file" >&2; exit 1; }
done

# An exact lightweight tag must exist before the draft is created so tagged
# distribution checkout is a real Git ref, not only draft release metadata.
grep -F 'git/ref/tags/$release_tag' "$PUBLISH" >/dev/null
grep -F '"ref=refs/tags/$release_tag"' "$PUBLISH" >/dev/null
grep -F '"sha=$target_sha"' "$PUBLISH" >/dev/null
grep -F -- '--verify-tag' "$PUBLISH" >/dev/null
grep -F -- '--draft' "$PUBLISH" >/dev/null
grep -F 'Realigned draft release' "$PUBLISH" >/dev/null
grep -F 'Reusing matching draft release' "$PUBLISH" >/dev/null
grep -F 'gh workflow run build-dist.yml' "$PUBLISH" >/dev/null

# Tag lookups must branch on gh's exit status. A 404 JSON error body must never
# be captured through `|| true` and mistaken for a SHA.
if grep -nE 'git/ref/tags/.*\|\|[[:space:]]*true' "$PUBLISH" "$BUILD"; then
  echo "Do not suppress tag-ref lookup failures into nonempty JSON values." >&2
  exit 1
fi
grep -F 'if tag_sha="$(gh api' "$PUBLISH" >/dev/null
grep -F 'if ! tag_sha="$(gh api' "$BUILD" >/dev/null

tag_line="$(grep -nF '"ref=refs/tags/$release_tag"' "$PUBLISH" | cut -d: -f1)"
create_line="$(grep -nF 'gh release create "$release_tag"' "$PUBLISH" | cut -d: -f1)"
[[ -n "$tag_line" && -n "$create_line" && "$tag_line" -lt "$create_line" ]] || {
  echo "Release tag must be created/verified before draft Release creation." >&2
  exit 1
}

# Distribution builds verify the exact tag source, may repair draft assets, and
# must never replace a published release.
grep -F 'git/ref/tags/$RELEASE_TAG' "$BUILD" >/dev/null
grep -F 'not checked-out source' "$BUILD" >/dev/null
grep -F 'refusing to alter published assets' "$BUILD" >/dev/null
grep -F 'gh release upload "$RELEASE_TAG"' "$BUILD" >/dev/null
grep -F 'gh release edit "$RELEASE_TAG" --draft=false' "$BUILD" >/dev/null

attach_line="$(grep -nF 'gh release upload "$RELEASE_TAG"' "$BUILD" | cut -d: -f1)"
publish_line="$(grep -nF 'gh release edit "$RELEASE_TAG" --draft=false' "$BUILD" | cut -d: -f1)"
[[ -n "$attach_line" && -n "$publish_line" && "$attach_line" -lt "$publish_line" ]] || {
  echo "Release assets must be attached before the draft is published." >&2
  exit 1
}

# Keep operator/agent docs version-neutral, current, and free of references to
# retired manual history ledgers.
! grep -F 'v1.0.0' "$README"
grep -F '**Publish release**' "$README" >/dev/null
grep -F '.github/release-request.json' "$AGENTS" >/dev/null
grep -F 'connector-only session' "$AGENTS" >/dev/null
for retired in 'BUILD-REVIEW.md' 'docs/validation-history.md'; do
  if grep -nF "$retired" "$README" "$VALIDATION" "$AGENTS" "$CONTRIBUTING"; then
    echo "Live authority docs reference retired history ledger: $retired" >&2
    exit 1
  fi
done
[[ ! -e "$ROOT/BUILD-REVIEW.md" ]] || { echo 'Retired BUILD-REVIEW.md must not return to the live tree.' >&2; exit 1; }
[[ ! -e "$ROOT/docs/validation-history.md" ]] || { echo 'Retired docs/validation-history.md must not return to the live tree.' >&2; exit 1; }

echo "Release workflow and AI-routing checks passed."
