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
mkdir -p "$UV_CACHE_DIR" "$UV_PYTHON_INSTALL_DIR" "$UV_TOOL_DIR" "$UV_TOOL_BIN_DIR" "$PIP_CACHE_DIR" "$NPM_CONFIG_CACHE" "$NPM_CONFIG_PREFIX" "$PYTHONPYCACHEPREFIX" "$ROOT/state/postgres"
export PATH="$ROOT/env/bin:$ROOT/bin:$UV_TOOL_BIN_DIR:$NPM_CONFIG_PREFIX/bin:$PATH"

"$ROOT/scripts/repair-python.sh" --quiet
python - <<'PY'
import csv, pathlib, sys, sysconfig, os
root=pathlib.Path(os.environ['MAGNET_AGENT_ENV']).resolve()
site=pathlib.Path(sysconfig.get_path('purelib')).resolve(); assert site.is_relative_to(root/'env')
for dist in sorted(site.glob('*.dist-info')):
    cache=dist/'uv_cache.json'; record=dist/'RECORD'; cache_record=f'{dist.name}/uv_cache.json'
    if cache.exists() or cache.is_symlink(): cache.unlink()
    if record.is_file():
        with record.open('r',encoding='utf-8',newline='') as h: rows=list(csv.reader(h))
        kept=[r for r in rows if not (r and r[0]==cache_record)]
        if len(kept)!=len(rows):
            with record.open('w',encoding='utf-8',newline='') as h: csv.writer(h,lineterminator='\n').writerows(kept)
assert pathlib.Path(sys.prefix).resolve()==root/'env'
base=(root/'runtime/python/current').resolve()
assert pathlib.Path(sysconfig.get_config_var('BINDIR')).resolve()==base/'bin'
assert pathlib.Path(sysconfig.get_config_var('LIBDIR')).resolve()==base/'lib'
assert '__MAGNET_AGENT_PYTHON_PREFIX__' not in repr(sysconfig.get_config_vars())
import httpx, jsonschema, packaging, yaml, tomlkit, rpds  # noqa: F401
from yaml import CLoader
assert CLoader is not None
print('python-ok',sys.version.split()[0])
PY

real_python="$(readlink -f "$ROOT/env/bin/.python-real")"
case "$real_python" in "$ROOT/runtime/python/"*) ;; *) echo "Venv interpreter escapes bundled runtime: $real_python" >&2; exit 1;; esac

uv --version
gh --version
node --version
npm --version
jq --version
yq --version
rg --version
actionlint --version
gitleaks version
shellcheck --version | grep -F 'version: 0.11.0' >/dev/null
mlr --version | grep -F '6.20.2' >/dev/null
httpx --help >/dev/null
pip --version >/dev/null
printf '{"a":1}\n' | jq -e '.a == 1' >/dev/null
printf 'a: 1\n' | yq -e '.a == 1' >/dev/null
printf 'magnet\n' | rg -q magnet
node -e 'if (process.versions.node !== "24.19.0") process.exit(1)'

TMP="$(mktemp -d "${TMPDIR:-/tmp}/agent-env-selftest.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
printf '#!/bin/sh\nprintf "ok\\n"\n' > "$TMP/good.sh"
printf '#!/bin/sh\necho $UNQUOTED\n' > "$TMP/bad.sh"
shellcheck "$TMP/good.sh" >/dev/null
if shellcheck "$TMP/bad.sh" >/dev/null 2>&1; then echo 'ShellCheck negative probe unexpectedly passed.' >&2; exit 1; fi
printf 'name,count\na,1\nb,2\n' | mlr --icsv --ojson filter '$count > 1' then put '$double=$count*2' > "$TMP/mlr.json"
python - <<'PY' "$TMP/mlr.json"
import json,sys
x=json.load(open(sys.argv[1])); assert x==[{'name':'b','count':2,'double':4}],x
PY

python - <<'PY'
import http.server, socketserver, subprocess, threading
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body=b'agent-env-httpx-ok\n'
        self.send_response(200)
        self.send_header('Content-Type','text/plain; charset=utf-8')
        self.send_header('Content-Length',str(len(body)))
        self.end_headers(); self.wfile.write(body)
    def log_message(self,*a): pass
with socketserver.TCPServer(('127.0.0.1',0),H) as s:
    t=threading.Thread(target=s.handle_request); t.start()
    p=subprocess.run(['httpx',f'http://127.0.0.1:{s.server_address[1]}'],text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    t.join(5); assert p.returncode==0,p.stdout; assert 'agent-env-httpx-ok' in p.stdout,p.stdout
PY

cat > "$TMP/pgtap.sql" <<'SQL'
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(2);
SELECT ok(1=1,'one equals one');
SELECT is(2,2,'two equals two');
SELECT * FROM finish();
ROLLBACK;
SQL
"$ROOT/bin/agent-env" postgres run --port 54322 -- bash -ceu '
  "$MAGNET_AGENT_ENV/bin/agent-env" pg psql -X -v ON_ERROR_STOP=1 -Atc "select version()" | grep -F "PostgreSQL 17.10" >/dev/null
  "$MAGNET_AGENT_ENV/bin/agent-env" pg psql -X -v ON_ERROR_STOP=1 -c "create extension if not exists plpgsql_check" >/dev/null
  "$MAGNET_AGENT_ENV/bin/agent-env" pg psql -X -v ON_ERROR_STOP=1 -c "create or replace function selftest_good() returns int language plpgsql as \$\$ begin return 1; end \$\$" >/dev/null
  "$MAGNET_AGENT_ENV/bin/agent-env" pg psql -X -Atc "select count(*) from plpgsql_check_function_tb('"'"'selftest_good()'"'"')" | grep -Fx 0 >/dev/null
  "$MAGNET_AGENT_ENV/bin/agent-env" pgtap '"$TMP"'/pgtap.sql
'

if find "$ROOT/state/postgres" -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
  echo 'PostgreSQL self-test left mutable cluster state.' >&2; exit 1
fi

while IFS= read -r -d '' link; do
  target="$(readlink "$link")"
  if [[ "$target" == /* ]]; then echo "Absolute symlink is not portable: $link -> $target" >&2; exit 1; fi
done < <(find "$ROOT" -type l ! -path "$ROOT/state/*" -print0)

echo "Runtime self-test passed."
