#!/usr/bin/env bash
set -euo pipefail
ROOT="${TEST_ROOT:-$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)}"
TOOL="$ROOT/scripts/check-version-transition.py"

pass_case() {
  python3 "$TOOL" --parent-version "$1" --current-version "$2" >/dev/null
}
fail_case() {
  if python3 "$TOOL" --parent-version "$1" --current-version "$2" >/dev/null 2>&1; then
    echo "Unexpected version-transition success: $*" >&2
    exit 1
  fi
}

pass_case 0.1.1 0.1.1
pass_case 0.1.1 0.1.2
pass_case 0.1.1 0.2.0-alpha.1
pass_case 0.2.0-alpha.1 0.2.0-alpha.2
pass_case 0.2.0-alpha.2 0.2.0-beta.1
pass_case 0.2.0-beta.1 0.2.0-rc.1
pass_case 0.2.0-rc.1 0.2.0-rc.2
pass_case 0.2.0-rc.2 0.2.0
pass_case 1.8.0-rc.1 2.0.0-rc.1

fail_case 0.2.0-rc.2 0.2.0-rc.1
fail_case 0.2.0 0.2.0-rc.3
fail_case 0.2.0-rc.1 0.2.0-dev
fail_case 0.2.0-rc.1 0.2.0-rc.0
fail_case 0.2.0-rc.1 0.2.0-preview.1

echo 'Version transition checks passed.'
