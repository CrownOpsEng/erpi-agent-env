#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
export ERPI_AGENT_ENV="$ROOT"
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
import csv, pathlib, sys, sysconfig, os
root=pathlib.Path(os.environ['ERPI_AGENT_ENV']).resolve()
site=pathlib.Path(sysconfig.get_path('purelib')).resolve(); assert site.is_relative_to(root/'env')
for dist in sorted(site.glob('*.dist-info')):
    cache=dist/'uv_cache.json'; record=dist/'RECORD'; cache_record=f'{dist.name}/uv_cache.json'
    assert not cache.exists() and not cache.is_symlink(), cache
    if record.is_file():
        with record.open('r',encoding='utf-8',newline='') as h: rows=list(csv.reader(h))
        assert not any(r and r[0]==cache_record for r in rows), cache_record
assert pathlib.Path(sys.prefix).resolve()==root/'env'
base=(root/'runtime/python/current').resolve()
assert pathlib.Path(sysconfig.get_config_var('BINDIR')).resolve()==base/'bin'
assert pathlib.Path(sysconfig.get_config_var('LIBDIR')).resolve()==base/'lib'
assert '__ERPI_AGENT_PYTHON_PREFIX__' not in repr(sysconfig.get_config_vars())
import httpx, jsonschema, packaging, yaml, tomlkit, rpds  # noqa: F401
from yaml import CLoader
from jsonschema import Draft202012Validator, FormatChecker
import rfc3339_validator  # noqa: F401
assert CLoader is not None
format_validator=Draft202012Validator(
    {'type':'string','format':'date-time'},
    format_checker=FormatChecker(),
)
assert format_validator.is_valid('2026-09-18T15:04:05Z')
assert not format_validator.is_valid('not-a-date-time')
print('python-ok',sys.version.split()[0])
PY
real_python="$(readlink -f "$ROOT/env/bin/.python-real")"
case "$real_python" in "$ROOT/runtime/python/"*) ;; *) echo "Venv interpreter escapes bundled runtime: $real_python" >&2; exit 1;; esac
httpx --help >/dev/null
pip --version >/dev/null
