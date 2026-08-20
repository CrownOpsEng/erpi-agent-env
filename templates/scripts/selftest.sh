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

python - <<'PY_META'
import csv, json, os, pathlib, re
root=pathlib.Path(os.environ['MAGNET_AGENT_ENV'])
env=json.loads((root/'manifest/environment.json').read_text(encoding='utf-8'))
python_meta=env['python_provenance']
assert python_meta['version']=='3.13.14'
assert python_meta['build']=='20260805'
assert re.fullmatch(r'[0-9a-f]{64}',python_meta['sha256'])
assert (root/'runtime/python/current/BUILD').read_text(encoding='utf-8').strip()==python_meta['build']
with (root/'manifest/sources.tsv').open('r',encoding='utf-8',newline='') as handle:
    rows=list(csv.reader(handle,delimiter='\t'))
assert rows and rows[0]==['component','version','url','sha256'], rows[:1]
assert all(len(row)==4 and all(cell for cell in row) for row in rows[1:]), rows
components={row[0] for row in rows[1:]}
assert {'python-build-standalone','postgres-server','node-postgres','pgls-wasm'} <= components
licenses=root/'licenses/third-party'
notice=licenses/'THIRD-PARTY-LICENSES.md'
assert notice.is_file() and notice.stat().st_size>10000,notice
PY_META

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
cleanup_tmp() { rm -rf "$TMP"; }
trap cleanup_tmp EXIT
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

# Prove the actual immutable Node capsules hydrate from the repository lock
# contract, execute, record content-bound ownership, and clean without network.
NODE_FIXTURE="$TMP/node-fixture"
mkdir -p "$NODE_FIXTURE"
printf '{"name":"agent-env-node-selftest","version":"1.0.0","type":"module"}\n' > "$NODE_FIXTURE/package.json"
python - <<'PY' "$ROOT/manifest/node-capsules.json" "$NODE_FIXTURE/package-lock.json"
import json,sys
manifest=json.load(open(sys.argv[1],encoding='utf-8'))
packages={"": {"name":"agent-env-node-selftest","version":"1.0.0"}}
for name,cap in manifest['packages'].items():
    packages[f'node_modules/{name}']={'version':cap['version'],'integrity':cap['integrity']}
json.dump({'name':'agent-env-node-selftest','version':'1.0.0','lockfileVersion':3,'requires':True,'packages':packages},open(sys.argv[2],'w',encoding='utf-8'),indent=2)
PY
"$ROOT/bin/agent-env" node-deps --repo "$NODE_FIXTURE" hydrate >/dev/null
(
  cd "$NODE_FIXTURE"
  node --input-type=module -e 'import postgres from "postgres"; import * as pgls from "@postgres-language-server/wasm"; import * as fc from "fast-check"; import { xoroshiro128plus } from "pure-rand/generator/xoroshiro128plus"; if(typeof postgres!=="function"||typeof pgls!=="object"||typeof fc.assert!=="function"||typeof xoroshiro128plus!=="function") process.exit(1)'
)
python - <<'PY' "$NODE_FIXTURE/node_modules/.agent-env-node-deps.json"
import json,re,sys
marker=json.load(open(sys.argv[1],encoding='utf-8'))
assert marker['schema']==2 and len(marker['packages'])==4
for record in marker['packages'].values(): assert re.fullmatch(r'[0-9a-f]{64}',record['tree_sha256'])
PY
"$ROOT/bin/agent-env" node-deps --repo "$NODE_FIXTURE" clean >/dev/null
[[ ! -e "$NODE_FIXTURE/node_modules/.agent-env-node-deps.json" ]]

cat > "$TMP/pgtap.sql" <<'SQL'
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(2);
SELECT ok(1=1,'one equals one');
SELECT is(2,2,'two equals two');
SELECT * FROM finish();
ROLLBACK;
SQL
cat > "$TMP/pgtap-bad.sql" <<'SQL'
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(1);
SELECT ok(false,'intentional negative self-test');
SELECT * FROM finish();
ROLLBACK;
SQL

free_port() {
  python - <<'PY'
import socket
with socket.socket(socket.AF_INET,socket.SOCK_STREAM) as s:
    s.bind(('127.0.0.1',0)); print(s.getsockname()[1])
PY
}
PG_PORT="$(free_port)"
"$ROOT/bin/agent-env" postgres run --port "$PG_PORT" -- bash -ceu '
  "$MAGNET_AGENT_ENV/bin/agent-env" pg psql -X -v ON_ERROR_STOP=1 -Atc "select version()" | grep -F "PostgreSQL 17.10" >/dev/null
  "$MAGNET_AGENT_ENV/bin/agent-env" pg psql -X -v ON_ERROR_STOP=1 -c "create extension if not exists plpgsql_check" >/dev/null
  "$MAGNET_AGENT_ENV/bin/agent-env" pg psql -X -v ON_ERROR_STOP=1 -c "create or replace function selftest_good() returns int language plpgsql as \$\$ begin return 1; end \$\$" >/dev/null
  "$MAGNET_AGENT_ENV/bin/agent-env" pg psql -X -Atc "select count(*) from plpgsql_check_function_tb('"'"'selftest_good()'"'"')" | grep -Fx 0 >/dev/null
  "$MAGNET_AGENT_ENV/bin/agent-env" pgtap '"$TMP"'/pgtap.sql >/dev/null
  if "$MAGNET_AGENT_ENV/bin/agent-env" pgtap '"$TMP"'/pgtap-bad.sql >/dev/null 2>&1; then echo "pgTAP negative probe unexpectedly passed" >&2; exit 1; fi
  "$MAGNET_AGENT_ENV/bin/agent-env" pg psql -X -v ON_ERROR_STOP=1 -c "create table selftest_data(id integer primary key, note text); insert into selftest_data values (1, '"'"'ok'"'"');" >/dev/null
  "$MAGNET_AGENT_ENV/bin/agent-env" pg pg_dump -Fc -f '"$TMP"'/selftest.dump postgres
  "$MAGNET_AGENT_ENV/bin/agent-env" pg createdb selftest_restore
  "$MAGNET_AGENT_ENV/bin/agent-env" pg pg_restore -d selftest_restore '"$TMP"'/selftest.dump
  "$MAGNET_AGENT_ENV/bin/agent-env" pg psql -X -d selftest_restore -Atc "select note from selftest_data where id=1" | grep -Fx ok >/dev/null
  "$MAGNET_AGENT_ENV/bin/agent-env" pg pg_amcheck --install-missing --database=postgres >/dev/null
  "$MAGNET_AGENT_ENV/bin/agent-env" pg pgbench -i -s 1 postgres >/dev/null
  "$MAGNET_AGENT_ENV/bin/agent-env" pg pgbench -c 2 -j 1 -t 2 postgres >/dev/null
'

# Nonzero child status must survive teardown and leave no cluster state.
NONZERO_PORT="$(free_port)"
set +e
"$ROOT/bin/agent-env" postgres run --port "$NONZERO_PORT" -- bash -c 'exit 23' >/dev/null 2>&1
nonzero_rc=$?
set -e
[[ "$nonzero_rc" == 23 ]] || { echo "PostgreSQL runner changed child exit 23 to $nonzero_rc" >&2; exit 1; }

# An interrupted command must still stop/check/delete its database cluster.
SIGNAL_PORT="$(free_port)"
SIGNAL_READY="$TMP/postgres-signal-ready"
"$ROOT/bin/agent-env" postgres run --port "$SIGNAL_PORT" -- python -c 'import pathlib,sys,time; pathlib.Path(sys.argv[1]).write_text("ready",encoding="utf-8"); time.sleep(30)' "$SIGNAL_READY" >/dev/null 2>&1 &
runner_pid=$!
ready=0
for (( attempt=0; attempt<100; attempt++ )); do
  if [[ -f "$SIGNAL_READY" ]]; then ready=1; break; fi
  sleep 0.05
done
(( ready == 1 )) || { kill -TERM "$runner_pid" 2>/dev/null || true; wait "$runner_pid" 2>/dev/null || true; echo 'PostgreSQL signal probe never reached child execution.' >&2; exit 1; }
kill -TERM "$runner_pid"
set +e
wait "$runner_pid"
signal_rc=$?
set -e
[[ "$signal_rc" != 0 ]] || { echo 'PostgreSQL signal probe unexpectedly returned success.' >&2; exit 1; }

if find "$ROOT/state/postgres" -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
  echo 'PostgreSQL self-test left mutable cluster state.' >&2; exit 1
fi
python - <<'PY' "$PG_PORT" "$NONZERO_PORT" "$SIGNAL_PORT"
import socket,sys
for raw in sys.argv[1:]:
    port=int(raw)
    with socket.socket(socket.AF_INET,socket.SOCK_STREAM) as s:
        s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
        s.bind(('127.0.0.1',port))
PY

while IFS= read -r -d '' link; do
  target="$(readlink "$link")"
  if [[ "$target" == /* ]]; then echo "Absolute symlink is not portable: $link -> $target" >&2; exit 1; fi
done < <(find "$ROOT" -type l ! -path "$ROOT/state/*" -print0)

echo "Runtime self-test passed."
