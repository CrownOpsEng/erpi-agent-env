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

version_change_is_release_metadata_only() {
  local parent="$1" current="$2"
  local changed=()
  mapfile -t changed < <(git diff --name-only "$parent" "$current" --)
  ((${#changed[@]} > 0)) || return 1

  local path
  for path in "${changed[@]}"; do
    case "$path" in
      versions.env|.github/release-request.json) ;;
      *) return 1 ;;
    esac
  done
  printf '%s\n' "${changed[@]}" | grep -Fx versions.env >/dev/null || return 1
  printf '%s\n' "${changed[@]}" | grep -Fx .github/release-request.json >/dev/null || return 1

  local parent_normalized current_normalized
  parent_normalized="$(git show "$parent:versions.env" | sed -E 's/^PRODUCT_VERSION="[^"]*"$/PRODUCT_VERSION="<VERSION>"/')"
  current_normalized="$(git show "$current:versions.env" | sed -E 's/^PRODUCT_VERSION="[^"]*"$/PRODUCT_VERSION="<VERSION>"/')"
  [[ "$parent_normalized" == "$current_normalized" ]]
}

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
    metadata_only=false
    if version_change_is_release_metadata_only "$parent" "$commit"; then
      metadata_only=true
    fi
    python3 "$ROOT/scripts/check-version-transition.py" \
      --parent-version "$parent_version" \
      --current-version "$current_version" \
      --metadata-only "$metadata_only" >/dev/null

    if [[ "$current_version" == "$parent_version" ]]; then
      [[ "$current_version" == "$base_version" ]] || {
        echo "Commit ${commit:0:12} continues source work with PRODUCT_VERSION $current_version before matching tag v$current_version exists; nearest source tag is $base_tag." >&2
        exit 1
      }
    else
      [[ "$metadata_only" == true ]] || {
        echo "PRODUCT_VERSION changes must touch only approved release metadata." >&2
        exit 1
      }
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

echo "Detailed commit history check passed for ${#commits[@]} commit(s)."
