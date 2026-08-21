#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
BASE_SHA="${1:-}"
HEAD_SHA="${2:-}"
ZERO_SHA="0000000000000000000000000000000000000000"

[[ "$HEAD_SHA" =~ ^[0-9a-f]{40}$ ]] || {
  echo "Commit-range check requires an exact 40-character head SHA." >&2
  exit 2
}
git cat-file -e "${HEAD_SHA}^{commit}" 2>/dev/null || {
  echo "Head commit is not available locally: $HEAD_SHA" >&2
  exit 2
}

commits=()
if [[ -z "$BASE_SHA" || "$BASE_SHA" == "$ZERO_SHA" ]]; then
  commits=("$HEAD_SHA")
else
  [[ "$BASE_SHA" =~ ^[0-9a-f]{40}$ ]] || {
    echo "Commit-range check requires an exact 40-character base SHA." >&2
    exit 2
  }
  git cat-file -e "${BASE_SHA}^{commit}" 2>/dev/null || {
    echo "Base commit is not available locally: $BASE_SHA" >&2
    exit 2
  }
  mapfile -t commits < <(git rev-list --reverse "${BASE_SHA}..${HEAD_SHA}")
fi

((${#commits[@]} > 0)) || {
  echo "No newly introduced commits to validate."
  exit 0
}

version_from_commit() {
  local commit="$1"
  local version
  version="$(git show "$commit:versions.env" | sed -n 's/^BUNDLE_VERSION="\([^"]*\)"$/\1/p')"
  [[ -n "$version" ]] || { echo "Could not resolve BUNDLE_VERSION at $commit" >&2; exit 1; }
  printf '%s\n' "$version"
}

version_change_is_metadata_only() {
  local parent="$1" current="$2"
  local changed=()
  mapfile -t changed < <(git diff --name-only "$parent" "$current" --)
  [[ ${#changed[@]} -eq 1 && "${changed[0]}" == versions.env ]] || return 1
  local parent_normalized current_normalized
  parent_normalized="$(git show "$parent:versions.env" | sed -E 's/^BUNDLE_VERSION="[^"]*"$/BUNDLE_VERSION="<VERSION>"/')"
  current_normalized="$(git show "$current:versions.env" | sed -E 's/^BUNDLE_VERSION="[^"]*"$/BUNDLE_VERSION="<VERSION>"/')"
  [[ "$parent_normalized" == "$current_normalized" ]]
}

for commit in "${commits[@]}"; do
  subject="$(git show -s --format=%s "$commit")"
  echo "Checking commit ${commit:0:12}: $subject"
  git show -s --format=%B "$commit" | python3 "$ROOT/scripts/check-commit-message.py"

  parent="$(git rev-parse "${commit}^1" 2>/dev/null || true)"
  if [[ -n "$parent" ]]; then
    parent_version="$(version_from_commit "$parent")"
    current_version="$(version_from_commit "$commit")"
    version_only=false
    if version_change_is_metadata_only "$parent" "$commit"; then version_only=true; fi
    python3 "$ROOT/scripts/check-version-transition.py" \
      --parent-version "$parent_version" \
      --current-version "$current_version" \
      --version-only "$version_only" >/dev/null
  fi
done

echo "Detailed commit history check passed for ${#commits[@]} commit(s)."
