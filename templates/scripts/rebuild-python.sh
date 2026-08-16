#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck disable=SC1091
source "$ROOT/manifest/versions.env"
[[ -x "$ROOT/runtime/python/current/bin/python${PYTHON_MINOR}" ]] || { echo "Bundled base Python is missing; offline rebuild cannot continue." >&2; exit 1; }
rm -rf "$ROOT/env"
UV_CACHE_DIR="$ROOT/state/uv-cache" UV_LINK_MODE=copy "$ROOT/bin/uv" venv --relocatable \
  --python "$ROOT/runtime/python/current/bin/python${PYTHON_MINOR}" "$ROOT/env"
rm -f "$ROOT/env/bin/python" "$ROOT/env/bin/python3" "$ROOT/env/bin/python${PYTHON_MINOR}" "$ROOT/env/bin/.python-real"
ln -s "../../runtime/python/current/bin/python${PYTHON_MINOR}" "$ROOT/env/bin/.python-real"
cp "$ROOT/scripts/python-wrapper.template" "$ROOT/env/bin/python"
chmod 0755 "$ROOT/env/bin/python"
ln -s python "$ROOT/env/bin/python3"
ln -s python "$ROOT/env/bin/python${PYTHON_MINOR}"
"$ROOT/scripts/repair-python.sh" --quiet
UV_CACHE_DIR="$ROOT/state/uv-cache" UV_LINK_MODE=copy "$ROOT/bin/uv" pip sync --offline \
  --python "$ROOT/env/bin/python" --require-hashes --no-index --find-links "$ROOT/wheelhouse" "$ROOT/manifest/requirements.lock"
"$ROOT/scripts/selftest.sh"
if [[ -f "$ROOT/manifest/SHA256SUMS" ]]; then
  "$ROOT/scripts/verify.sh" >/dev/null
fi
echo "Python environment rebuilt entirely from bundled artifacts."
