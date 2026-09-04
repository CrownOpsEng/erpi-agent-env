#!/usr/bin/env bash
set -euo pipefail
ROOT="${TEST_ROOT:-$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)}"
TOOL="$ROOT/scripts/build-identity.sh"
SHA="0123456789abcdef0123456789abcdef01234567"

check() {
  local product="$1" tag="$2" distance="$3" description="$4" expected_stem="$5"
  local output
  output="$("$TOOL" "$product" "$SHA" "$tag" "$distance" "$description" linux-x86_64-gnu)"
  grep -Fx "product_version=$product" <<<"$output" >/dev/null
  grep -Fx "source_commit=$SHA" <<<"$output" >/dev/null
  grep -Fx "source_base_tag=$tag" <<<"$output" >/dev/null
  grep -Fx "source_distance=$distance" <<<"$output" >/dev/null
  grep -Fx "source_description=$description" <<<"$output" >/dev/null
  grep -Fx "artifact_stem=$expected_stem" <<<"$output" >/dev/null
}

check 0.1.1 v0.1.1 0 v0.1.1 'erpi-agent-env-linux-x64-v0.1.1'
check 0.1.1 v0.1.1 17 v0.1.1-17-g0123456789ab 'erpi-agent-env-linux-x64-v0.1.1-17-g0123456789ab'
check 0.2.0-rc.1 v0.2.0-rc.1 0 v0.2.0-rc.1 'erpi-agent-env-linux-x64-v0.2.0-rc.1'
check 0.2.0-rc.1 v0.2.0-rc.1 2 v0.2.0-rc.1-2-g0123456789ab 'erpi-agent-env-linux-x64-v0.2.0-rc.1-2-g0123456789ab'
check 0.2.0-rc.1-2 v0.2.0-rc.1 2 v0.2.0-rc.1-2-g0123456789ab 'erpi-agent-env-linux-x64-v0.2.0-rc.1-2-g0123456789ab'
# A promotion commit can carry the next clean product version while source still describes from the prior tag.
check 0.2.0-rc.2 v0.2.0-rc.1 3 v0.2.0-rc.1-3-g0123456789ab 'erpi-agent-env-linux-x64-v0.2.0-rc.1-3-g0123456789ab'

if "$TOOL" 0.2.0-rc.1-1 "$SHA" v0.1.1 1 v0.1.1-1-g0123456789ab linux-x86_64-gnu >/dev/null 2>&1; then
  echo 'Build identity accepted a candidate-build revision detached from its published prerelease tag.' >&2
  exit 1
fi
if "$TOOL" 0.2.0-dev "$SHA" v0.1.1 1 v0.1.1-1-g0123456789ab linux-x86_64-gnu >/dev/null 2>&1; then
  echo 'Build identity accepted pseudo-development SemVer.' >&2
  exit 1
fi
if "$TOOL" 0.2.0 "$SHA" v0.2.0-rc.1 0 v0.2.0-rc.1 linux-x86_64-gnu >/dev/null 2>&1; then
  echo 'Build identity accepted an exact tag/product-version disagreement.' >&2
  exit 1
fi
if "$TOOL" 0.1.1 "$SHA" v0.1.1 2 v0.1.1-1-g0123456789ab linux-x86_64-gnu >/dev/null 2>&1; then
  echo 'Build identity accepted an incorrect commit distance.' >&2
  exit 1
fi
if "$TOOL" 0.1.1 deadbeef v0.1.1 1 v0.1.1-1-gdeadbeef linux-x86_64-gnu >/dev/null 2>&1; then
  echo 'Build identity accepted a non-exact source SHA.' >&2
  exit 1
fi

echo 'Build identity checks passed.'
