#!/usr/bin/env bash
set -euo pipefail
ROOT="${TEST_ROOT:-$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)}"
TOOL="$ROOT/scripts/check-version-transition.py"

pass_case() {
  python3 "$TOOL" --parent-version "$1" --current-version "$2" --version-only "$3" >/dev/null
}
fail_case() {
  if python3 "$TOOL" --parent-version "$1" --current-version "$2" --version-only "$3" >/dev/null 2>&1; then
    echo "Version transition unexpectedly passed: $1 -> $2 (version_only=$3)" >&2
    exit 1
  fi
}

pass_case 0.2.0-dev 0.2.0-dev false
pass_case 0.2.0-dev 0.3.0-dev false
pass_case 0.2.0-dev 0.2.0-rc.8 true
fail_case 0.2.0-dev 0.2.0-rc.8 false
fail_case 0.2.0-rc.8 0.2.0-rc.8 false
fail_case 0.2.0-rc.8 0.2.0-rc.9 true
pass_case 0.2.0-rc.8 0.2.0-dev false
fail_case 0.2.0-rc.8 0.3.0-dev false
pass_case 0.2.0-rc.8 0.2.0 true
fail_case 0.2.0-rc.8 0.2.0 false
fail_case 0.2.0-dev 0.2.0 true
fail_case 0.2.0 0.2.0 false
pass_case 0.2.0 0.2.1-dev false
pass_case 0.2.0 0.3.0-dev false

echo 'Version transition checks passed.'
