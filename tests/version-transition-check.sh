#!/usr/bin/env bash
set -euo pipefail
ROOT="${TEST_ROOT:-$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)}"
TOOL="$ROOT/scripts/check-version-transition.py"

pass_case() {
  python3 "$TOOL" --parent-version "$1" --current-version "$2" --metadata-only "$3" >/dev/null
}
fail_case() {
  if python3 "$TOOL" --parent-version "$1" --current-version "$2" --metadata-only "$3" >/dev/null 2>&1; then
    echo "Unexpected version-transition success: $*" >&2
    exit 1
  fi
}

pass_case 0.1.1 0.1.1 false
pass_case 0.1.1 0.1.2 true
pass_case 0.1.1 0.2.0-alpha.1 true
pass_case 0.2.0-alpha.1 0.2.0-alpha.1-1 false
pass_case 0.2.0-alpha.1-1 0.2.0-alpha.1-2 false
pass_case 0.2.0-alpha.1-2 0.2.0-alpha.2 true
pass_case 0.2.0-alpha.2 0.2.0-beta.1 true
pass_case 0.2.0-beta.1 0.2.0-rc.1 true
pass_case 0.2.0-rc.1 0.2.0-rc.1-1 false
pass_case 0.2.0-rc.1-1 0.2.0-rc.1-2 false
pass_case 0.2.0-rc.1-2 0.2.0-rc.2 true
pass_case 0.2.0-rc.2 0.2.0 true
pass_case 1.8.0-rc.1-3 2.0.0-rc.1 true

fail_case 0.1.1 0.2.0-rc.1 false
fail_case 0.2.0-rc.1-2 0.2.0-rc.1-1 false
fail_case 0.2.0-rc.1-1 0.2.0-rc.1 true
fail_case 0.2.0-rc.1-1 0.2.0-rc.2 false
fail_case 0.2.0-beta.1-2 0.2.0-rc.1-1 false
fail_case 0.2.0 0.2.0-rc.3 true
fail_case 0.2.0-rc.1 0.2.0-dev true
fail_case 0.2.0-rc.1 0.2.0-rc.0 true
fail_case 0.2.0-rc.1 0.2.0-rc.1-0 false
fail_case 0.2.0-rc.1 0.2.0-preview.1 true

echo 'Version transition checks passed.'
