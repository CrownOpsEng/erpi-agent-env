#!/usr/bin/env bash
set -euo pipefail
SOURCE_ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
ROOT="$T/Runtime Root – moved"
mkdir -p "$ROOT/scripts" "$ROOT/manifest" "$ROOT/env" "$ROOT/runtime/python/cpython-test/bin"
cp "$SOURCE_ROOT/templates/scripts/repair-python.sh" "$ROOT/scripts/repair-python.sh"
chmod 0755 "$ROOT/scripts/repair-python.sh"
cat > "$ROOT/manifest/versions.env" <<'VERSIONS'
PYTHON_VERSION="3.13.14"
PYTHON_MINOR="3.13"
VERSIONS
: > "$ROOT/runtime/python/cpython-test/bin/python3.13"
chmod 0755 "$ROOT/runtime/python/cpython-test/bin/python3.13"
ln -s cpython-test "$ROOT/runtime/python/current"
cat > "$ROOT/env/pyvenv.cfg" <<'CFG'
home = /old/location/bin
implementation = CPython
uv = 0.12.5
version_info = 3.13.14
include-system-site-packages = false
relocatable = true
prompt = do-not-touch
CFG
"$ROOT/scripts/repair-python.sh" --quiet
expected_home="home = $ROOT/runtime/python/current/bin"
grep -Fx "$expected_home" "$ROOT/env/pyvenv.cfg" >/dev/null
grep -Fx 'implementation = CPython' "$ROOT/env/pyvenv.cfg" >/dev/null
grep -Fx 'uv = 0.12.5' "$ROOT/env/pyvenv.cfg" >/dev/null
grep -Fx 'relocatable = true' "$ROOT/env/pyvenv.cfg" >/dev/null
grep -Fx 'prompt = do-not-touch' "$ROOT/env/pyvenv.cfg" >/dev/null
! grep -q '^executable = ' "$ROOT/env/pyvenv.cfg"
cp "$ROOT/env/pyvenv.cfg" "$T/before"
"$ROOT/scripts/repair-python.sh" --quiet
cmp -s "$T/before" "$ROOT/env/pyvenv.cfg"
rm "$ROOT/runtime/python/current"
if "$ROOT/scripts/repair-python.sh" --quiet >"$T/out" 2>"$T/err"; then
  echo "repair-python unexpectedly reconstructed immutable Python topology" >&2
  exit 1
fi
grep -F 'Bundled Python topology is invalid' "$T/err" >/dev/null
echo "Python metadata repair check passed."
