#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
PUBLISH="$ROOT/.github/workflows/publish-release.yml"
BUILD="$ROOT/.github/workflows/build-dist.yml"
README="$ROOT/README.md"
AGENTS="$ROOT/AGENTS.md"

for file in "$PUBLISH" "$BUILD" "$README" "$AGENTS"; do
  [[ -s "$file" ]] || { echo "Required release-routing source missing: $file" >&2; exit 1; }
done

# Release creation must stop at a recoverable draft until accepted assets exist.
grep -F -- '--draft' "$PUBLISH" >/dev/null
grep -F 'Reusing matching draft release' "$PUBLISH" >/dev/null
grep -F 'gh workflow run build-dist.yml' "$PUBLISH" >/dev/null

# Distribution builds may repair draft assets, but must never replace a published release.
grep -F 'refusing to replace published assets' "$BUILD" >/dev/null
grep -F 'Reconfirm draft release' "$BUILD" >/dev/null
grep -F 'gh release upload "$RELEASE_TAG"' "$BUILD" >/dev/null
grep -F 'gh release edit "$RELEASE_TAG" --draft=false' "$BUILD" >/dev/null

attach_line="$(grep -nF 'gh release upload "$RELEASE_TAG"' "$BUILD" | cut -d: -f1)"
publish_line="$(grep -nF 'gh release edit "$RELEASE_TAG" --draft=false' "$BUILD" | cut -d: -f1)"
[[ -n "$attach_line" && -n "$publish_line" && "$attach_line" -lt "$publish_line" ]] || {
  echo "Release assets must be attached before the draft is published." >&2
  exit 1
}

# Keep operator/agent docs version-neutral and aware of the durable publisher.
! grep -F 'v1.0.0' "$README"
grep -F '**Publish release**' "$README" >/dev/null
grep -F '.github/release-request.json' "$AGENTS" >/dev/null
grep -F 'connector-only session' "$AGENTS" >/dev/null

echo "Release workflow and AI-routing checks passed."
