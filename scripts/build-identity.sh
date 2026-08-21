#!/usr/bin/env bash
set -euo pipefail

compute_build_identity() {
  local bundle_version="${1:-}"
  local source_commit="${2:-}"
  local target="${3:-}"

  [[ "$bundle_version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-dev|-rc\.[1-9][0-9]*)?$ ]] || {
    echo "Unsupported BUNDLE_VERSION lifecycle identity: $bundle_version" >&2
    return 2
  }
  [[ "$source_commit" =~ ^[0-9a-f]{40}$ ]] || {
    echo "Source commit must be an exact 40-character lowercase Git SHA." >&2
    return 2
  }

  local artifact_platform
  case "$target" in
    linux-x86_64-gnu) artifact_platform="linux-x64" ;;
    *) echo "Unsupported artifact target for build identity: $target" >&2; return 2 ;;
  esac

  if [[ "$bundle_version" == *-dev ]]; then
    BUILD_ID="${bundle_version}+g${source_commit:0:12}"
  else
    BUILD_ID="$bundle_version"
  fi
  ARTIFACT_STEM="magnet-agent-env-${artifact_platform}-v${BUILD_ID}"
  export BUILD_ID ARTIFACT_STEM
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  [[ $# -eq 3 ]] || {
    echo "Usage: $0 BUNDLE_VERSION SOURCE_COMMIT TARGET" >&2
    exit 2
  }
  compute_build_identity "$1" "$2" "$3"
  printf 'build_id=%s\nartifact_stem=%s\n' "$BUILD_ID" "$ARTIFACT_STEM"
fi
