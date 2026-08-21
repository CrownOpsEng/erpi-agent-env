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
import csv, hashlib, json, os, pathlib, re
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
assert {'python-build-standalone','postgres-server-source','postgres-server-build-image','postgres-server-build-flex','node-postgres','pgls-wasm','pg-delta-lock'} <= components
licenses=root/'licenses/third-party'
notice=licenses/'THIRD-PARTY-LICENSES.md'
assert notice.is_file() and notice.stat().st_size>10000,notice
pg_delta=env['capabilities']['pg_delta']
assert pg_delta=={'version':'1.0.0-alpha.33','supabase_cli_baseline':'2.114.0','surface':'plan-only','live_connections':'numeric-loopback-only'},pg_delta
versions=(root/'manifest/versions.env').read_text(encoding='utf-8')
lock_hash=re.search(r'^PG_DELTA_LOCK_SHA256="([0-9a-f]{64})"$',versions,re.M).group(1)
assert hashlib.sha256((root/'manifest/pg-delta-package-lock.json').read_bytes()).hexdigest()==lock_hash
assert not (root/'runtime/pg-delta/node_modules/.bin').exists(), 'upstream pgdelta CLI shim must not be exposed'
assert (root/'licenses/pg-delta/LICENSE').is_file()
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
import http.server, os, socketserver, subprocess, threading
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
    # The probe is deliberately run with dead inherited-style proxies. Local
    # runtime verification must never depend on the host's proxy policy.
    probe_env=os.environ.copy()
    dead_proxy='http://127.0.0.1:9'
    for key in ('HTTP_PROXY','HTTPS_PROXY','ALL_PROXY','http_proxy','https_proxy','all_proxy'):
        probe_env[key]=dead_proxy
    probe_env['NO_PROXY']='127.0.0.1,localhost'
    probe_env['no_proxy']='127.0.0.1,localhost'
    p=subprocess.run(['httpx',f'http://127.0.0.1:{s.server_address[1]}'],text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,env=probe_env)
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

# pg-delta is deliberately plan-only and refuses any non-loopback live target
# before attempting a database connection or creating output.
if "$ROOT/bin/agent-env" pg-delta apply >/dev/null 2>&1; then
  echo 'pg-delta apply unexpectedly exposed an upstream mutation command.' >&2
  exit 1
fi
if "$ROOT/bin/agent-env" pg-delta plan \
  --source 'postgresql://postgres@127.0.0.1:1/source_db' \
  --target 'postgresql://postgres@198.51.100.10/remote_db' \
  --out "$TMP/pgdelta-remote-rejected" >/dev/null 2>&1; then
  echo 'pg-delta accepted a remote database URL.' >&2
  exit 1
fi
[[ ! -e "$TMP/pgdelta-remote-rejected" ]] || { echo 'Rejected pg-delta target created output.' >&2; exit 1; }

cat > "$TMP/pgdelta-source.sql" <<'SQL'
create schema delta_probe;
revoke all on schema delta_probe from public;

create table delta_probe.entities (
  id bigint generated always as identity primary key,
  canonical_name text,
  state text not null default 'candidate',
  created_at timestamptz not null default now(),
  constraint entities_state_check check (state in ('candidate','active'))
);

create table delta_probe.notes (
  id bigint generated always as identity primary key,
  entity_id bigint not null references delta_probe.entities(id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now()
);

create index notes_entity_idx on delta_probe.notes(entity_id);
SQL

cat > "$TMP/pgdelta-target.sql" <<'SQL'
create schema delta_probe;
revoke all on schema delta_probe from public;

create domain delta_probe.nonempty_text as text
  check (value is null or btrim(value) <> '');

create table delta_probe.entities (
  id bigint generated always as identity primary key,
  canonical_name text,
  external_ref delta_probe.nonempty_text,
  state text not null default 'candidate',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint entities_state_check check (state in ('candidate','active','archived'))
);

create table delta_probe.notes (
  id bigint generated always as identity primary key,
  entity_id bigint not null references delta_probe.entities(id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now()
);

create index notes_entity_idx on delta_probe.notes(entity_id);
create index notes_recent_idx on delta_probe.notes(created_at) where body <> '';

create or replace function delta_probe.notes_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.body = '' then
    raise exception 'empty note';
  end if;
  return new;
end
$$;

create trigger "notes-guard"
before insert or update on delta_probe.notes
for each row execute function delta_probe.notes_guard();

create schema auth;
create table auth.managed_noise(id bigint primary key);
SQL

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

  for db in pgdelta_source pgdelta_target pgdelta_clone; do
    "$MAGNET_AGENT_ENV/bin/agent-env" pg createdb "$db"
  done
  "$MAGNET_AGENT_ENV/bin/agent-env" pg psql -X -v ON_ERROR_STOP=1 -d pgdelta_source -f '"$TMP"'/pgdelta-source.sql >/dev/null
  "$MAGNET_AGENT_ENV/bin/agent-env" pg psql -X -v ON_ERROR_STOP=1 -d pgdelta_target -f '"$TMP"'/pgdelta-target.sql >/dev/null
  "$MAGNET_AGENT_ENV/bin/agent-env" pg pg_dump --schema-only --no-owner pgdelta_source \
    | "$MAGNET_AGENT_ENV/bin/agent-env" pg psql -X -v ON_ERROR_STOP=1 -d pgdelta_clone >/dev/null
  source_url="postgresql://postgres@127.0.0.1:${PGPORT}/pgdelta_source"
  target_url="postgresql://postgres@127.0.0.1:${PGPORT}/pgdelta_target"
  clone_url="postgresql://postgres@127.0.0.1:${PGPORT}/pgdelta_clone"
  before_source="$("$MAGNET_AGENT_ENV/bin/agent-env" pg pg_dump --schema-only --no-owner --restrict-key=MagnetAgentEnvSelftest pgdelta_source | sha256sum | cut -d" " -f1)"
  before_target="$("$MAGNET_AGENT_ENV/bin/agent-env" pg pg_dump --schema-only --no-owner --restrict-key=MagnetAgentEnvSelftest pgdelta_target | sha256sum | cut -d" " -f1)"
  "$MAGNET_AGENT_ENV/bin/agent-env" pg-delta plan --source "$source_url" --target "$target_url" --out '"$TMP"'/pgdelta-plan >/dev/null
  test -s '"$TMP"'/pgdelta-plan/envelope.json
  cat '"$TMP"'/pgdelta-plan/*.sql > '"$TMP"'/pgdelta-plan.sql
  grep -F "nonempty_text" '"$TMP"'/pgdelta-plan.sql >/dev/null
  grep -F "updated_at" '"$TMP"'/pgdelta-plan.sql >/dev/null
  grep -F "notes_recent_idx" '"$TMP"'/pgdelta-plan.sql >/dev/null
  grep -F "notes-guard" '"$TMP"'/pgdelta-plan.sql >/dev/null
  ! grep -F "auth.managed_noise" '"$TMP"'/pgdelta-plan.sql >/dev/null
  for file in '"$TMP"'/pgdelta-plan/*.sql; do
    "$MAGNET_AGENT_ENV/bin/agent-env" pg psql -X -v ON_ERROR_STOP=1 -d pgdelta_clone -f "$file" >/dev/null
  done
  "$MAGNET_AGENT_ENV/bin/agent-env" pg-delta plan --source "$clone_url" --target "$target_url" --out '"$TMP"'/pgdelta-convergence >/dev/null
  "$MAGNET_AGENT_ENV/runtime/node/bin/node" -e "const fs=require(\"node:fs\"); const e=JSON.parse(fs.readFileSync(process.argv[1],\"utf8\")); if(e.files.length) { console.error(e); process.exit(1) }" '"$TMP"'/pgdelta-convergence/envelope.json
  after_source="$("$MAGNET_AGENT_ENV/bin/agent-env" pg pg_dump --schema-only --no-owner --restrict-key=MagnetAgentEnvSelftest pgdelta_source | sha256sum | cut -d" " -f1)"
  after_target="$("$MAGNET_AGENT_ENV/bin/agent-env" pg pg_dump --schema-only --no-owner --restrict-key=MagnetAgentEnvSelftest pgdelta_target | sha256sum | cut -d" " -f1)"
  [[ "$before_source" == "$after_source" && "$before_target" == "$after_target" ]] || { echo "pg-delta plan mutated source or target" >&2; exit 1; }

  "$MAGNET_AGENT_ENV/bin/agent-env" pg psql -X -v ON_ERROR_STOP=1 -c "create table selftest_data(id integer primary key, note text); insert into selftest_data values (1, '"'"'ok'"'"');" >/dev/null
  "$MAGNET_AGENT_ENV/bin/agent-env" pg pg_dump -Fc -f '"$TMP"'/selftest.dump postgres
  "$MAGNET_AGENT_ENV/bin/agent-env" pg createdb selftest_restore
  "$MAGNET_AGENT_ENV/bin/agent-env" pg pg_restore -d selftest_restore '"$TMP"'/selftest.dump
  "$MAGNET_AGENT_ENV/bin/agent-env" pg psql -X -d selftest_restore -Atc "select note from selftest_data where id=1" | grep -Fx ok >/dev/null
  "$MAGNET_AGENT_ENV/bin/agent-env" pg pg_amcheck --install-missing --database=postgres >/dev/null
  "$MAGNET_AGENT_ENV/bin/agent-env" pg pgbench -i -s 1 postgres >/dev/null
  "$MAGNET_AGENT_ENV/bin/agent-env" pg pgbench -c 2 -j 1 -t 2 postgres >/dev/null
'

# An alternate bootstrap identity allows faithful non-superuser role emulation.
BOOTSTRAP_PORT="$(free_port)"
"$ROOT/bin/agent-env" postgres run --bootstrap-user agent_env_bootstrap --port "$BOOTSTRAP_PORT" -- bash -ceu '
  test "$PGUSER" = agent_env_bootstrap
  test "$DATABASE_URL" = "postgresql://agent_env_bootstrap:postgres@127.0.0.1:${PGPORT}/postgres"
  "$MAGNET_AGENT_ENV/bin/agent-env" pg psql -X -v ON_ERROR_STOP=1 -At -F: -c "select current_user, rolsuper::int from pg_roles where rolname=current_user" | grep -Fx "agent_env_bootstrap:1" >/dev/null
  "$MAGNET_AGENT_ENV/bin/agent-env" pg psql -X -v ON_ERROR_STOP=1 -c "create role postgres login nosuperuser createrole" >/dev/null
  PGUSER=postgres "$MAGNET_AGENT_ENV/bin/agent-env" pg psql -X -v ON_ERROR_STOP=1 -At -F: -c "select rolsuper::int, rolcreaterole::int from pg_roles where rolname=current_user" | grep -Fx "0:1" >/dev/null
  PGUSER=postgres "$MAGNET_AGENT_ENV/bin/agent-env" pg psql -X -v ON_ERROR_STOP=1 -c "alter default privileges for role postgres revoke execute on functions from public" >/dev/null
  PGUSER=postgres "$MAGNET_AGENT_ENV/bin/agent-env" pg psql -X -v ON_ERROR_STOP=1 -c "create role agent_env_child_role" >/dev/null
  if PGUSER=postgres "$MAGNET_AGENT_ENV/bin/agent-env" pg psql -X -v ON_ERROR_STOP=1 -c "create role agent_env_forbidden_superuser superuser" >/dev/null 2>&1; then
    echo "non-superuser postgres unexpectedly created a superuser" >&2
    exit 1
  fi
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
python - <<'PY' "$PG_PORT" "$BOOTSTRAP_PORT" "$NONZERO_PORT" "$SIGNAL_PORT"
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
