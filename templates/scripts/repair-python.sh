#!/usr/bin/env bash
set -euo pipefail
QUIET=0
[[ "${1:-}" == "--quiet" ]] && QUIET=1
ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck disable=SC1091
source "$ROOT/manifest/versions.env"
PYROOT_LINK="$ROOT/runtime/python/current"

# The current link is immutable payload topology. Relocation may change the
# bundle root, but it must never require reconstructing this link.
[[ -L "$PYROOT_LINK" ]] || { echo "Bundled Python topology is invalid: runtime/python/current is missing or not a symlink." >&2; exit 1; }
link_target="$(readlink "$PYROOT_LINK")"
[[ "$link_target" != /* ]] || { echo "Bundled Python topology is invalid: runtime/python/current is absolute." >&2; exit 1; }
[[ -x "$PYROOT_LINK/bin/python${PYTHON_MINOR}" ]] || { echo "Bundled Python ${PYTHON_VERSION} is missing behind runtime/python/current." >&2; exit 1; }
resolved_root="$(CDPATH= cd -- "$PYROOT_LINK" && pwd -P)"
case "$resolved_root" in
  "$ROOT/runtime/python/"*) ;;
  *) echo "Bundled Python topology is invalid: runtime/python/current escapes the bundle." >&2; exit 1 ;;
esac

CFG="$ROOT/env/pyvenv.cfg"
[[ -f "$CFG" ]] || { echo "Python venv metadata is missing: $CFG" >&2; exit 1; }
home_count="$(grep -c '^home = ' "$CFG" 2>/dev/null || true)"
[[ "$home_count" == 1 ]] || { echo "Python venv metadata must contain exactly one home entry." >&2; exit 1; }
expected_home="home = $PYROOT_LINK/bin"
current_home="$(grep '^home = ' "$CFG")"
if [[ "$current_home" != "$expected_home" ]]; then
  TMP="$CFG.$$"
  awk -v replacement="$expected_home" '
    /^home = / { print replacement; next }
    { print }
  ' "$CFG" > "$TMP"
  mv -f "$TMP" "$CFG"
  (( QUIET )) || echo "Repaired Python venv home for $ROOT"
fi
