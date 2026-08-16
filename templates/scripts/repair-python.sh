#!/usr/bin/env bash
set -euo pipefail
QUIET=0
[[ "${1:-}" == "--quiet" ]] && QUIET=1
ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck disable=SC1091
source "$ROOT/manifest/versions.env"
PYROOT_LINK="$ROOT/runtime/python/current"
if [[ ! -e "$PYROOT_LINK/bin/python${PYTHON_MINOR}" ]]; then
  candidate="$(find "$ROOT/runtime/python" -mindepth 2 -maxdepth 3 -path "*/bin/python${PYTHON_MINOR}" -print -quit 2>/dev/null || true)"
  [[ -n "$candidate" ]] || { echo "Bundled Python ${PYTHON_VERSION} is missing." >&2; exit 1; }
  install_root="$(CDPATH= cd -- "$(dirname -- "$candidate")/.." && pwd -P)"
  rm -f "$PYROOT_LINK"
  ln -s "$(basename -- "$install_root")" "$PYROOT_LINK"
fi
CFG="$ROOT/env/pyvenv.cfg"
TMP="$CFG.$$"
expected="home = $PYROOT_LINK/bin
implementation = CPython
uv = $UV_VERSION
version_info = $PYTHON_VERSION
include-system-site-packages = false
relocatable = true
executable = $PYROOT_LINK/bin/python${PYTHON_MINOR}"
current="$(cat "$CFG" 2>/dev/null || true)"
if [[ "$current" != "$expected" ]]; then
  printf '%s\n' "$expected" > "$TMP"
  mv -f "$TMP" "$CFG"
  (( QUIET )) || echo "Repaired Python venv paths for $ROOT"
fi
