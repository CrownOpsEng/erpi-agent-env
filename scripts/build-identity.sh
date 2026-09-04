#!/usr/bin/env bash
set -euo pipefail

VERSION_ERE='(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-(alpha|beta|rc)\.[1-9][0-9]*)?'

compute_build_identity() {
  local product_version="${1:-}"
  local source_commit="${2:-}"
  local source_base_tag="${3:-}"
  local source_distance="${4:-}"
  local source_description="${5:-}"
  local target="${6:-}"

  [[ "$product_version" =~ ^${VERSION_ERE}$ ]] || {
    echo "Unsupported PRODUCT_VERSION: $product_version" >&2
    return 2
  }
  [[ "$source_commit" =~ ^[0-9a-f]{40}$ ]] || {
    echo "Source commit must be an exact 40-character lowercase Git SHA." >&2
    return 2
  }
  [[ "$source_base_tag" =~ ^v${VERSION_ERE}$ ]] || {
    echo "Source base tag must be v<SemVer> using optional alpha.N, beta.N, or rc.N prerelease syntax." >&2
    return 2
  }
  [[ "$source_distance" =~ ^(0|[1-9][0-9]*)$ ]] || {
    echo "Source distance must be a non-negative base-10 integer without leading zeroes." >&2
    return 2
  }

  local tag_version="${source_base_tag#v}"
  local expected_description
  if [[ "$source_distance" == 0 ]]; then
    expected_description="$source_base_tag"
    [[ "$product_version" == "$tag_version" ]] || {
      echo "Exact tagged source $source_base_tag must match PRODUCT_VERSION $product_version." >&2
      return 2
    }
  else
    expected_description="${source_base_tag}-${source_distance}-g${source_commit:0:12}"
  fi
  [[ "$source_description" == "$expected_description" ]] || {
    echo "Source description $source_description does not match expected ancestry $expected_description." >&2
    return 2
  }

  local artifact_platform
  case "$target" in
    linux-x86_64-gnu) artifact_platform="linux-x64" ;;
    *) echo "Unsupported artifact target for source identity: $target" >&2; return 2 ;;
  esac

  PRODUCT_VERSION_ID="$product_version"
  SOURCE_COMMIT_ID="$source_commit"
  SOURCE_BASE_TAG_ID="$source_base_tag"
  SOURCE_DISTANCE_ID="$source_distance"
  SOURCE_DESCRIPTION_ID="$source_description"
  ARTIFACT_STEM="erpi-agent-env-${artifact_platform}-${source_description}"
  export PRODUCT_VERSION_ID SOURCE_COMMIT_ID SOURCE_BASE_TAG_ID SOURCE_DISTANCE_ID SOURCE_DESCRIPTION_ID ARTIFACT_STEM
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  [[ $# -eq 6 ]] || {
    echo "Usage: $0 PRODUCT_VERSION SOURCE_COMMIT SOURCE_BASE_TAG SOURCE_DISTANCE SOURCE_DESCRIPTION TARGET" >&2
    exit 2
  }
  compute_build_identity "$@"
  printf 'product_version=%s\nsource_commit=%s\nsource_base_tag=%s\nsource_distance=%s\nsource_description=%s\nartifact_stem=%s\n' \
    "$PRODUCT_VERSION_ID" "$SOURCE_COMMIT_ID" "$SOURCE_BASE_TAG_ID" "$SOURCE_DISTANCE_ID" "$SOURCE_DESCRIPTION_ID" "$ARTIFACT_STEM"
fi
