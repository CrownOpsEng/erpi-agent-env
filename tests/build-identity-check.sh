#!/usr/bin/env bash
set -euo pipefail
ROOT="${TEST_ROOT:-$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)}"
TOOL="$ROOT/scripts/build-identity.sh"
SHA="0123456789abcdef0123456789abcdef01234567"

check() {
  local version="$1" expected_id="$2" expected_stem="$3"
  local output
  output="$("$TOOL" "$version" "$SHA" linux-x86_64-gnu)"
  grep -Fx "build_id=$expected_id" <<<"$output" >/dev/null
  grep -Fx "artifact_stem=$expected_stem" <<<"$output" >/dev/null
}

check 0.2.0-dev '0.2.0-dev+g0123456789ab' 'magnet-agent-env-linux-x64-v0.2.0-dev+g0123456789ab'
check 0.2.0-rc.8 '0.2.0-rc.8' 'magnet-agent-env-linux-x64-v0.2.0-rc.8'
check 0.2.0 '0.2.0' 'magnet-agent-env-linux-x64-v0.2.0'

if "$TOOL" 0.2.0-dev deadbeef linux-x86_64-gnu >/dev/null 2>&1; then
  echo 'Build identity accepted a non-exact source SHA.' >&2
  exit 1
fi
if "$TOOL" 0.2.0-rc.0 "$SHA" linux-x86_64-gnu >/dev/null 2>&1; then
  echo 'Build identity accepted an invalid RC identity.' >&2
  exit 1
fi
if "$TOOL" 0.2.0-dev "$SHA" linux-arm64 >/dev/null 2>&1; then
  echo 'Build identity accepted an unsupported artifact target.' >&2
  exit 1
fi

echo 'Build identity checks passed.'
