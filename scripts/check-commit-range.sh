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

product_version_from_commit() {
  local commit="$1" text version
  text="$(git show "$commit:versions.env")"
  version="$(sed -n 's/^PRODUCT_VERSION="\([^"]*\)"$/\1/p' <<<"$text")"
  [[ -n "$version" ]] || return 1
  printf '%s\n' "$version"
}

legacy_bundle_version_from_commit() {
  local commit="$1"
  git show "$commit:versions.env" | sed -n 's/^BUNDLE_VERSION="\([^"]*\)"$/\1/p'
}

release_request_version_from_commit() {
  local commit="$1"
  git show "$commit:.github/release-request.json" 2>/dev/null | python3 -c '
import json,sys
try:
    data=json.load(sys.stdin)
except Exception as exc:
    raise SystemExit(f"invalid release-request.json: {exc}")
if set(data) != {"version"} or not isinstance(data["version"], str):
    raise SystemExit("release-request.json must contain exactly one string field: version")
print(data["version"])
'
}

source_base_tag() {
  local commit="$1"
  git describe --tags --match 'v[0-9]*' --abbrev=0 --first-parent "$commit" 2>/dev/null || {
    echo "No reachable v<SemVer> source tag for $commit" >&2
    exit 1
  }
}

range_contains_version_change=false
for commit in "${commits[@]}"; do
  subject="$(git show -s --format=%s "$commit")"
  echo "Checking commit ${commit:0:12}: $subject"
  git show -s --format=%B "$commit" | python3 "$ROOT/scripts/check-commit-message.py"

  current_version="$(product_version_from_commit "$commit")" || {
    echo "Commit $commit must define PRODUCT_VERSION in versions.env; BUNDLE_VERSION is obsolete." >&2
    exit 1
  }
  base_tag="$(source_base_tag "$commit")"
  base_version="${base_tag#v}"

  parent="$(git rev-parse "${commit}^1" 2>/dev/null || true)"
  [[ -n "$parent" ]] || continue

  if parent_version="$(product_version_from_commit "$parent" 2>/dev/null)"; then
    python3 "$ROOT/scripts/check-version-transition.py" \
      --parent-version "$parent_version" \
      --current-version "$current_version" >/dev/null

    if [[ "$current_version" != "$parent_version" ]]; then
      range_contains_version_change=true
      request_version="$(release_request_version_from_commit "$commit")"
      [[ "$request_version" == "$current_version" ]] || {
        echo "Release request version $request_version does not match PRODUCT_VERSION $current_version at ${commit:0:12}." >&2
        exit 1
      }
    fi
  else
    legacy_version="$(legacy_bundle_version_from_commit "$parent")"
    [[ -n "$legacy_version" ]] || {
      echo "Parent $parent has neither PRODUCT_VERSION nor legacy BUNDLE_VERSION." >&2
      exit 1
    }
    [[ "$current_version" == "$base_version" ]] || {
      echo "Legacy version-authority migration must attach PRODUCT_VERSION to nearest released tag $base_tag, not $current_version." >&2
      exit 1
    }
    request_version="$(release_request_version_from_commit "$commit")"
    [[ "$request_version" == "$current_version" ]] || {
      echo "Migrated release request version $request_version does not match PRODUCT_VERSION $current_version." >&2
      exit 1
    }
    echo "Accepted one-time legacy version-authority migration from $legacy_version to released product $current_version."
  fi
done

head_version="$(product_version_from_commit "$HEAD_SHA")"
head_base_tag="$(source_base_tag "$HEAD_SHA")"
head_base_version="${head_base_tag#v}"
if [[ "$range_contains_version_change" != true && "$head_version" != "$head_base_version" ]]; then
  echo "Introduced source continues with PRODUCT_VERSION $head_version before matching tag v$head_version exists; nearest source tag is $head_base_tag." >&2
  exit 1
fi

echo "Detailed commit history check passed for ${#commits[@]} commit(s)."
