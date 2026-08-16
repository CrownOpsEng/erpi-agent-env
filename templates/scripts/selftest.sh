#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
export MAGNET_AGENT_ENV="$ROOT"
export VIRTUAL_ENV="$ROOT/env"
export UV_CACHE_DIR="$ROOT/state/uv-cache"
export UV_PYTHON_INSTALL_DIR="$ROOT/state/uv-python"
export UV_TOOL_DIR="$ROOT/state/uv-tools"
export UV_TOOL_BIN_DIR="$ROOT/state/uv-tool-bin"
export PIP_CACHE_DIR="$ROOT/state/pip-cache"
export NPM_CONFIG_CACHE="$ROOT/state/npm-cache"
export NPM_CONFIG_PREFIX="$ROOT/state/npm-global"
export UV_LINK_MODE=copy
export PYTHONPYCACHEPREFIX="$ROOT/state/pycache"
mkdir -p "$UV_CACHE_DIR" "$UV_PYTHON_INSTALL_DIR" "$UV_TOOL_DIR" "$UV_TOOL_BIN_DIR" "$PIP_CACHE_DIR" "$NPM_CONFIG_CACHE" "$NPM_CONFIG_PREFIX" "$PYTHONPYCACHEPREFIX"
export PATH="$ROOT/env/bin:$ROOT/bin:$UV_TOOL_BIN_DIR:$NPM_CONFIG_PREFIX/bin:$PATH"

"$ROOT/scripts/repair-python.sh" --quiet
python - <<'PY'
import pathlib, sys, sysconfig
root = pathlib.Path(__import__('os').environ['MAGNET_AGENT_ENV']).resolve()
assert pathlib.Path(sys.prefix).resolve() == root / 'env', (sys.prefix, root)
base = (root / 'runtime/python/current').resolve()
bindir = pathlib.Path(sysconfig.get_config_var('BINDIR')).resolve()
libdir = pathlib.Path(sysconfig.get_config_var('LIBDIR')).resolve()
assert bindir == base / 'bin', (bindir, base)
assert libdir == base / 'lib', (libdir, base)
assert '__MAGNET_AGENT_PYTHON_PREFIX__' not in repr(sysconfig.get_config_vars())
import httpx, jsonschema, packaging, yaml, tomlkit, pytest  # noqa: F401
print('python-ok', sys.version.split()[0])
PY
real_python="$(readlink -f "$ROOT/env/bin/.python-real")"
case "$real_python" in
  "$ROOT/runtime/python/"*) ;;
  *) echo "Venv interpreter escapes bundled runtime: $real_python" >&2; exit 1 ;;
esac
uv --version
gh --version
node --version
npm --version
jq --version
yq --version
rg --version
actionlint --version
gitleaks version
printf '{"a":1}\n' | jq -e '.a == 1' >/dev/null
printf 'a: 1\n' | yq -e '.a == 1' >/dev/null
printf 'magnet\n' | rg -q magnet
node -e 'if (process.versions.node.split(".")[0] !== "24") process.exit(1)'
python -m pytest --version >/dev/null

# Every script in env/bin must either be a portable shell launcher, a relative
# symlink, or one of our explicit Python binaries/wrappers. Absolute build-root
# shebangs are forbidden by the builder's residue gate.
while IFS= read -r -d '' link; do
  target="$(readlink "$link")"
  if [[ "$target" == /* ]]; then
    echo "Absolute symlink is not portable: $link -> $target" >&2
    exit 1
  fi
done < <(find "$ROOT" -type l ! -path "$ROOT/state/*" -print0)

echo "Runtime self-test passed."
