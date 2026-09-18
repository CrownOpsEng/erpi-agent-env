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
mkdir -p "$UV_CACHE_DIR" "$UV_PYTHON_INSTALL_DIR" "$UV_TOOL_DIR" "$UV_TOOL_BIN_DIR" "$PIP_CACHE_DIR" "$NPM_CONFIG_CACHE" "$NPM_CONFIG_PREFIX" "$PYTHONPYCACHEPREFIX" "$ROOT/state/postgres"
export PATH="$ROOT/env/bin:$ROOT/bin:$UV_TOOL_BIN_DIR:$NPM_CONFIG_PREFIX/bin:$PATH"

"$ROOT/scripts/python-smoke.sh"

python - <<'PY_META'
import csv, hashlib, json, os, pathlib, re
root=pathlib.Path(os.environ['ERPI_AGENT_ENV'])
env=json.loads((root/'manifest/environment.json').read_text(encoding='utf-8'))
product_version=env['product_version']
source=env['source']
source_commit=source['commit']
source_description=source['description']
source_base_tag=source['base_tag']
source_distance=source['distance']
assert re.fullmatch(r'\d+\.\d+\.\d+(?:-(?:alpha|beta|rc)\.[1-9]\d*(?:-[1-9]\d*)?)?',product_version),product_version
assert re.fullmatch(r'[0-9a-f]{40}',source_commit),source_commit
assert re.fullmatch(r'v\d+\.\d+\.\d+(?:-(?:alpha|beta|rc)\.[1-9]\d*)?',source_base_tag),source_base_tag
assert isinstance(source_distance,int) and source_distance >= 0,source_distance
if source_distance == 0:
    assert source_description == source_base_tag,(source_description,source_base_tag)
    assert product_version == source_base_tag[1:],(product_version,source_base_tag)
else:
    assert source_description == f'{source_base_tag}-{source_distance}-g{source_commit[:12]}',source_description
    candidate=re.fullmatch(r'(\d+\.\d+\.\d+-(?:alpha|beta|rc)\.[1-9]\d*)-[1-9]\d*',product_version)
    if candidate:
        assert candidate.group(1) == source_base_tag[1:],(product_version,source_base_tag)
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
assert {'python-build-standalone','postgres-server-source','postgres-server-build-image','postgres-server-build-flex','postgrest','supabase-cli','node-postgres','pgls-wasm','pg-delta-lock'} <= components
licenses=root/'licenses/third-party'
notice=licenses/'THIRD-PARTY-LICENSES.md'
assert notice.is_file() and notice.stat().st_size>10000,notice
pg_delta=env['capabilities']['pg_delta']
assert pg_delta=={'version':'1.0.0-alpha.49','pg_topo_version':'1.0.0-alpha.6','pg_client_version':'8.23.0','supabase_cli_baseline':'2.117.0','surface':'plan-only','live_connections':'numeric-loopback-only'},pg_delta
versions=(root/'manifest/versions.env').read_text(encoding='utf-8')
lock_hash=re.search(r'^PG_DELTA_LOCK_SHA256="([0-9a-f]{64})"$',versions,re.M).group(1)
assert hashlib.sha256((root/'manifest/pg-delta-package-lock.json').read_bytes()).hexdigest()==lock_hash
assert not (root/'runtime/pg-delta/node_modules/.bin').exists(), 'upstream pgdelta CLI shim must not be exposed'
assert (root/'licenses/pg-delta/LICENSE').is_file()
postgrest=env['capabilities']['postgrest']
assert postgrest=={'version':'16.2','supabase_cli_baseline':'2.117.0','database_targets':'numeric-loopback-only','http_listener':'loopback-only'},postgrest
assert (root/'licenses/postgrest/LICENSE').is_file()
supabase=env['capabilities']['supabase_cli']
assert supabase=={'version':'2.117.0','distribution':'official-linux-amd64','companion':'bundled-supabase-go','credentials':'host/session','container_runtime':'host-required-for-stack-commands'},supabase
assert (root/'licenses/supabase/LICENSE').is_file()
assert (root/'runtime/supabase/supabase').is_file() and (root/'runtime/supabase/supabase-go').is_file()
assert not (root/'bin/supabase-go').exists(), 'supabase-go companion must not be ambient PATH surface'
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
"$ROOT/runtime/postgrest/postgrest" --version | grep -Fx 'PostgREST 16.2' >/dev/null
supabase --version | grep -Fx '2.117.0' >/dev/null
"$ROOT/runtime/supabase/supabase-go" --version | grep -Fx '2.117.0' >/dev/null
printf '{"a":1}\n' | jq -e '.a == 1' >/dev/null
printf 'a: 1\n' | yq -e '.a == 1' >/dev/null
printf 'agent-env\n' | rg -q agent-env
node -e 'if (process.versions.node !== "24.19.0") process.exit(1)'
TMP="$(mktemp -d "${TMPDIR:-/tmp}/agent-env-selftest.XXXXXX")"
cleanup_tmp() { rm -rf "$TMP"; }
trap cleanup_tmp EXIT

SUPABASE_FIXTURE="$TMP/supabase-fixture"
mkdir -p "$SUPABASE_FIXTURE"
(
  cd "$SUPABASE_FIXTURE"
  HOME="$TMP/supabase-home" XDG_CONFIG_HOME="$TMP/supabase-home/.config" XDG_CACHE_HOME="$TMP/supabase-home/.cache" SUPABASE_TELEMETRY_DISABLED=1 supabase init --yes </dev/null >/dev/null
  test -f supabase/config.toml
  HOME="$TMP/supabase-home" XDG_CONFIG_HOME="$TMP/supabase-home/.config" XDG_CACHE_HOME="$TMP/supabase-home/.cache" SUPABASE_TELEMETRY_DISABLED=1 supabase migration new runtime_probe </dev/null >/dev/null
  mapfile -t supabase_migrations < <(find supabase/migrations -maxdepth 1 -type f -name '*_runtime_probe.sql' -print)
  [[ ${#supabase_migrations[@]} -eq 1 ]]
)
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

# When host Git is available, prove a connector-style full Git bundle can be
# restored entirely offline by the shipped command while hostile Git state is ignored.
if command -v git >/dev/null 2>&1; then
  (
    set -euo pipefail
    GIT_HANDOFF_SRC="$TMP/git-handoff-source"
    GIT_HANDOFF_HOME="$TMP/git-handoff-home"
    GIT_HANDOFF_ARTIFACT="$TMP/git-handoff.zip"
    GIT_HANDOFF_DEST="$TMP/git-handoff-restored"
    mkdir -p "$GIT_HANDOFF_HOME"
    export HOME="$GIT_HANDOFF_HOME"
    export GIT_CONFIG_NOSYSTEM=1
    export GIT_CONFIG_GLOBAL=/dev/null
    unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_CONFIG_COUNT || true

    git init --quiet "$GIT_HANDOFF_SRC"
    git -C "$GIT_HANDOFF_SRC" branch -m main
    git -C "$GIT_HANDOFF_SRC" config user.name 'Agent Env Runtime Fixture'
    git -C "$GIT_HANDOFF_SRC" config user.email 'runtime-fixture@example.invalid'
    printf 'base\n' > "$GIT_HANDOFF_SRC/base.txt"
    git -C "$GIT_HANDOFF_SRC" add base.txt
    git -C "$GIT_HANDOFF_SRC" commit --quiet -m base
    git -C "$GIT_HANDOFF_SRC" tag runtime-fixture-base
    git -C "$GIT_HANDOFF_SRC" switch --quiet -c feature/runtime-handoff
    printf 'feature\n' > "$GIT_HANDOFF_SRC/feature.txt"
    git -C "$GIT_HANDOFF_SRC" add feature.txt
    git -C "$GIT_HANDOFF_SRC" commit --quiet -m feature
    handoff_sha="$(git -C "$GIT_HANDOFF_SRC" rev-parse HEAD)"
    git -C "$GIT_HANDOFF_SRC" bundle create "$TMP/git-handoff.bundle" --all

    python - "$TMP/git-handoff.bundle" "$GIT_HANDOFF_ARTIFACT" "$handoff_sha" <<'PY_GIT_HANDOFF'
import sys,zipfile
bundle,out,sha=sys.argv[1:]
with zipfile.ZipFile(out,'w',compression=zipfile.ZIP_DEFLATED) as z:
    z.write(bundle,'repository.bundle')
    z.writestr('SOURCE_SHA',sha+'\n')
    z.writestr('SOURCE_BRANCH','feature/runtime-handoff\n')
    z.writestr('REPOSITORY','CrownOpsEng/runtime-selftest\n')
PY_GIT_HANDOFF
    cat > "$TMP/git-handoff-poison" <<'EOF_GIT_HANDOFF'
[credential "https://github.com"]
	helper = !echo SHOULD_NOT_LEAK
[http "https://github.com/"]
	extraheader = AUTHORIZATION: poison
[url "https://attacker.invalid/"]
	insteadOf = https://github.com/
EOF_GIT_HANDOFF
    GIT_DIR=/not/a/repository GIT_CONFIG_GLOBAL="$TMP/git-handoff-poison" \
      "$ROOT/bin/agent-env" git-handoff restore "$GIT_HANDOFF_ARTIFACT" "$GIT_HANDOFF_DEST" >/dev/null
    [[ "$(git -C "$GIT_HANDOFF_DEST" rev-parse HEAD)" == "$handoff_sha" ]]
    [[ "$(git -C "$GIT_HANDOFF_DEST" rev-parse '@{upstream}')" == "$handoff_sha" ]]
    [[ "$(git -C "$GIT_HANDOFF_DEST" branch --show-current)" == 'feature/runtime-handoff' ]]
    [[ "$(git -C "$GIT_HANDOFF_DEST" remote get-url origin)" == 'https://github.com/CrownOpsEng/runtime-selftest.git' ]]
    [[ "$(git -C "$GIT_HANDOFF_DEST" rev-parse runtime-fixture-base)" != '' ]]
    [[ -z "$(git -C "$GIT_HANDOFF_DEST" status --porcelain=v1 --untracked-files=all)" ]]

    python - "$GIT_HANDOFF_ARTIFACT" "$TMP/git-handoff-bad.zip" <<'PY_GIT_HANDOFF_BAD'
import sys,zipfile
src,out=sys.argv[1:]
with zipfile.ZipFile(src) as zin, zipfile.ZipFile(out,'w',compression=zipfile.ZIP_DEFLATED) as zout:
    for info in zin.infolist():
        data=zin.read(info)
        if info.filename=='SOURCE_SHA': data=b'0000000000000000000000000000000000000000\n'
        zout.writestr(info.filename,data)
PY_GIT_HANDOFF_BAD
    if "$ROOT/bin/agent-env" git-handoff restore "$TMP/git-handoff-bad.zip" "$TMP/git-handoff-bad-dest" >/dev/null 2>&1; then
      echo 'Git handoff runtime negative probe unexpectedly passed.' >&2
      exit 1
    fi
    [[ ! -e "$TMP/git-handoff-bad-dest" ]]
  )
fi

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
  node --input-type=module -e 'import { parse as parseYaml, stringify as stringifyYaml } from "yaml"; import postgres from "postgres"; import * as pgls from "@postgres-language-server/wasm"; import * as fc from "fast-check"; import { xoroshiro128plus } from "pure-rand/generator/xoroshiro128plus"; import { Command } from "commander"; const parsed=parseYaml("enabled: true\n"); if(parsed.enabled!==true||parseYaml(stringifyYaml(parsed)).enabled!==true||typeof postgres!=="function"||typeof pgls!=="object"||typeof fc.assert!=="function"||typeof xoroshiro128plus!=="function"||typeof Command!=="function") process.exit(1)'
)
python - <<'PY' "$NODE_FIXTURE/node_modules/.agent-env-node-deps.json"
import json,re,sys
marker=json.load(open(sys.argv[1],encoding='utf-8'))
assert marker['schema']==2 and len(marker['packages'])==6
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
# PostgREST refuses remote database targeting before starting a service.
POSTGREST_REJECT_PORT="$(free_port)"
if "$ROOT/bin/agent-env" postgrest run \
  --db-uri 'postgresql://authenticator@198.51.100.10/postgres' \
  --db-schemas api --db-anon-role anon --port "$POSTGREST_REJECT_PORT" -- true >/dev/null 2>&1; then
  echo 'PostgREST accepted a remote database URL.' >&2
  exit 1
fi

cat > "$TMP/postgrest-fixture.sql" <<'SQL'
create role authenticator login nosuperuser noinherit;
create role anon nologin nosuperuser;
create role executor_ok nologin nosuperuser;
create role executor_bad nologin nosuperuser;
grant anon to authenticator;
grant set on parameter "agent.pre_ran" to anon;

create schema api;
create schema core;
revoke all on schema api, core from public;

create table core.events(label text primary key);
revoke all on table core.events from public;

create function core.invoker_write(p_label text)
returns text
language plpgsql
security invoker
set search_path = ''
as $$
begin
  insert into core.events(label) values (p_label);
  return p_label;
end
$$;

create function api.pre_request()
returns void
language plpgsql
security invoker
as $$
begin
  perform pg_catalog.set_config('agent.pre_ran', 'yes', true);
end
$$;

create function api.context_probe()
returns jsonb
language sql
stable
security invoker
as $$
  select pg_catalog.jsonb_build_object(
    'current_user', current_user,
    'session_user', session_user,
    'search_path', pg_catalog.current_setting('search_path'),
    'pre', pg_catalog.current_setting('agent.pre_ran', true)
  )
$$;

create function api.write_ok()
returns text
language plpgsql
security definer
set search_path = ''
as $$
begin
  return core.invoker_write('ok');
end
$$;

create function api.write_denied()
returns text
language plpgsql
security definer
set search_path = ''
as $$
begin
  return core.invoker_write('denied');
end
$$;

alter function api.write_ok() owner to executor_ok;
alter function api.write_denied() owner to executor_bad;
revoke all on all functions in schema api, core from public;

grant usage on schema api to anon, executor_ok, executor_bad;
grant execute on function api.pre_request() to anon;
grant execute on function api.context_probe() to anon;
grant execute on function api.write_ok() to anon;
grant execute on function api.write_denied() to anon;

grant usage on schema core to executor_ok;
grant execute on function core.invoker_write(text) to executor_ok, executor_bad;
grant insert, select on table core.events to executor_ok, executor_bad;
SQL

cat > "$TMP/postgrest-probe.py" <<'PY'
import http.client, json, os
from urllib.parse import urlsplit
url=urlsplit(os.environ['POSTGREST_URL'])

def rpc(name):
    conn=http.client.HTTPConnection(url.hostname,url.port,timeout=5)
    conn.request('POST',f'/rpc/{name}',body=b'{}',headers={'Content-Type':'application/json'})
    response=conn.getresponse(); body=response.read(); conn.close()
    return response.status,body

status,body=rpc('context_probe')
assert status==200,(status,body)
context=json.loads(body)
assert context['current_user']=='anon',context
assert context['session_user']=='authenticator',context
assert 'api' in context['search_path'],context
assert context['pre']=='yes',context
status,body=rpc('write_ok')
assert status==200,(status,body)
status,body=rpc('write_denied')
assert status>=400,(status,body)
error=json.loads(body)
assert error.get('code')=='42501',error
PY

cat > "$TMP/postgrest-sleeper.py" <<'PY'
import os,pathlib,time
pathlib.Path(os.environ['POSTGREST_SIGNAL_READY']).write_text('ready',encoding='utf-8')
time.sleep(30)
PY

POSTGREST_PG_PORT="$(free_port)"
POSTGREST_HTTP_PORT="$(free_port)"
POSTGREST_SIGNAL_PORT="$(free_port)"
POSTGREST_FIXTURE="$TMP/postgrest-fixture.sql" \
POSTGREST_PROBE="$TMP/postgrest-probe.py" \
POSTGREST_SLEEPER="$TMP/postgrest-sleeper.py" \
POSTGREST_HTTP_PORT="$POSTGREST_HTTP_PORT" \
POSTGREST_SIGNAL_PORT="$POSTGREST_SIGNAL_PORT" \
POSTGREST_SIGNAL_READY="$TMP/postgrest-signal-ready" \
"$ROOT/bin/agent-env" postgres run --bootstrap-user agent_env_postgrest_bootstrap --port "$POSTGREST_PG_PORT" -- bash -ceu '
  "$ERPI_AGENT_ENV/bin/agent-env" pg psql -X -v ON_ERROR_STOP=1 -f "$POSTGREST_FIXTURE" >/dev/null
  db_uri="postgresql://authenticator@127.0.0.1:${PGPORT}/postgres"
  "$ERPI_AGENT_ENV/bin/agent-env" postgrest run \
    --db-uri "$db_uri" --db-schemas api --db-anon-role anon \
    --db-pre-request api.pre_request --port "$POSTGREST_HTTP_PORT" -- \
    python "$POSTGREST_PROBE"
  "$ERPI_AGENT_ENV/bin/agent-env" pg psql -X -Atc "select label from core.events order by label" | grep -Fx ok >/dev/null

  POSTGREST_SIGNAL_READY="$POSTGREST_SIGNAL_READY" \
  "$ERPI_AGENT_ENV/bin/agent-env" postgrest run \
    --db-uri "$db_uri" --db-schemas api --db-anon-role anon \
    --db-pre-request api.pre_request --port "$POSTGREST_SIGNAL_PORT" -- \
    python "$POSTGREST_SLEEPER" >/dev/null 2>&1 &
  postgrest_runner=$!
  ready=0
  for (( attempt=0; attempt<100; attempt++ )); do
    if [[ -f "$POSTGREST_SIGNAL_READY" ]]; then ready=1; break; fi
    sleep 0.05
  done
  (( ready == 1 )) || { kill -TERM "$postgrest_runner" 2>/dev/null || true; wait "$postgrest_runner" 2>/dev/null || true; echo "PostgREST signal probe never reached child execution." >&2; exit 1; }
  kill -TERM "$postgrest_runner"
  set +e
  wait "$postgrest_runner"
  signal_rc=$?
  set -e
  [[ "$signal_rc" != 0 ]] || { echo "PostgREST signal probe unexpectedly returned success." >&2; exit 1; }
'

if find "$ROOT/state/postgrest" -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
  echo 'PostgREST self-test left mutable service state.' >&2
  exit 1
fi

PG_PORT="$(free_port)"
"$ROOT/bin/agent-env" postgres run --port "$PG_PORT" -- bash -ceu '
  "$ERPI_AGENT_ENV/bin/agent-env" pg psql -X -v ON_ERROR_STOP=1 -Atc "select version()" | grep -F "PostgreSQL 17.10" >/dev/null
  "$ERPI_AGENT_ENV/bin/agent-env" pg psql -X -v ON_ERROR_STOP=1 -c "create extension if not exists plpgsql_check" >/dev/null
  "$ERPI_AGENT_ENV/bin/agent-env" pg psql -X -v ON_ERROR_STOP=1 -c "create or replace function selftest_good() returns int language plpgsql as \$\$ begin return 1; end \$\$" >/dev/null
  "$ERPI_AGENT_ENV/bin/agent-env" pg psql -X -Atc "select count(*) from plpgsql_check_function_tb('"'"'selftest_good()'"'"')" | grep -Fx 0 >/dev/null
  "$ERPI_AGENT_ENV/bin/agent-env" pgtap '"$TMP"'/pgtap.sql >/dev/null
  if "$ERPI_AGENT_ENV/bin/agent-env" pgtap '"$TMP"'/pgtap-bad.sql >/dev/null 2>&1; then echo "pgTAP negative probe unexpectedly passed" >&2; exit 1; fi

  for db in pgdelta_source pgdelta_target pgdelta_clone pgdelta_coverage; do
    "$ERPI_AGENT_ENV/bin/agent-env" pg createdb "$db"
  done
  "$ERPI_AGENT_ENV/bin/agent-env" pg psql -X -v ON_ERROR_STOP=1 -d pgdelta_source -f '"$TMP"'/pgdelta-source.sql >/dev/null
  "$ERPI_AGENT_ENV/bin/agent-env" pg psql -X -v ON_ERROR_STOP=1 -d pgdelta_target -f '"$TMP"'/pgdelta-target.sql >/dev/null
  "$ERPI_AGENT_ENV/bin/agent-env" pg psql -X -v ON_ERROR_STOP=1 -d pgdelta_coverage -f '"$TMP"'/pgdelta-source.sql >/dev/null
  "$ERPI_AGENT_ENV/bin/agent-env" pg psql -X -v ON_ERROR_STOP=1 -d pgdelta_coverage -c "create statistics delta_probe.notes_coverage_stats on entity_id, created_at from delta_probe.notes" >/dev/null
  "$ERPI_AGENT_ENV/bin/agent-env" pg pg_dump --schema-only --no-owner pgdelta_source \
    | "$ERPI_AGENT_ENV/bin/agent-env" pg psql -X -v ON_ERROR_STOP=1 -d pgdelta_clone >/dev/null
  source_url="postgresql://postgres@127.0.0.1:${PGPORT}/pgdelta_source"
  target_url="postgresql://postgres@127.0.0.1:${PGPORT}/pgdelta_target"
  clone_url="postgresql://postgres@127.0.0.1:${PGPORT}/pgdelta_clone"
  coverage_url="postgresql://postgres@127.0.0.1:${PGPORT}/pgdelta_coverage"
  if "$ERPI_AGENT_ENV/bin/agent-env" pg-delta plan --source "$coverage_url" --target "$target_url" --out '"$TMP"'/pgdelta-coverage-plan >'"$TMP"'/pgdelta-coverage.stdout 2>'"$TMP"'/pgdelta-coverage.stderr; then
    echo "pg-delta strict coverage unexpectedly accepted an unmodeled statistics object" >&2
    exit 1
  fi
  grep -F "strict coverage gate refused an incomplete pg-delta plan" '"$TMP"'/pgdelta-coverage.stderr >/dev/null
  grep -F "unmodeled_kind" '"$TMP"'/pgdelta-coverage.stderr >/dev/null
  [[ ! -e '"$TMP"'/pgdelta-coverage-plan ]] || { echo "Rejected pg-delta coverage plan created output." >&2; exit 1; }
  before_source="$("$ERPI_AGENT_ENV/bin/agent-env" pg pg_dump --schema-only --no-owner --restrict-key=ERPIAgentEnvSelftest pgdelta_source | sha256sum | cut -d" " -f1)"
  before_target="$("$ERPI_AGENT_ENV/bin/agent-env" pg pg_dump --schema-only --no-owner --restrict-key=ERPIAgentEnvSelftest pgdelta_target | sha256sum | cut -d" " -f1)"
  "$ERPI_AGENT_ENV/bin/agent-env" pg-delta plan --source "$source_url" --target "$target_url" --out '"$TMP"'/pgdelta-plan >/dev/null
  test -s '"$TMP"'/pgdelta-plan/envelope.json
  "$ERPI_AGENT_ENV/runtime/node/bin/node" -e "const fs=require(\"node:fs\"); const e=JSON.parse(fs.readFileSync(process.argv[1],\"utf8\")); if(e.pgDeltaVersion!==\"1.0.0-alpha.49\"||e.supabaseCliBaseline!==\"2.117.0\"||e.profile!==\"supabase\"||!Array.isArray(e.files)) { console.error(e); process.exit(1) }" '"$TMP"'/pgdelta-plan/envelope.json
  cat '"$TMP"'/pgdelta-plan/*.sql > '"$TMP"'/pgdelta-plan.sql
  grep -F "nonempty_text" '"$TMP"'/pgdelta-plan.sql >/dev/null
  grep -F "updated_at" '"$TMP"'/pgdelta-plan.sql >/dev/null
  grep -F "notes_recent_idx" '"$TMP"'/pgdelta-plan.sql >/dev/null
  grep -F "notes-guard" '"$TMP"'/pgdelta-plan.sql >/dev/null
  ! grep -F "auth.managed_noise" '"$TMP"'/pgdelta-plan.sql >/dev/null
  tab="$(printf "\\t")"
  while IFS="$tab" read -r transaction_mode relative_path; do
    test -n "$relative_path"
    plan_file='"$TMP"'/pgdelta-plan/$relative_path
    test -f "$plan_file"
    case "$transaction_mode" in
      transactional)
        "$ERPI_AGENT_ENV/bin/agent-env" pg psql -X -v ON_ERROR_STOP=1 --single-transaction -d pgdelta_clone -f "$plan_file" >/dev/null
        ;;
      none)
        "$ERPI_AGENT_ENV/bin/agent-env" pg psql -X -v ON_ERROR_STOP=1 -d pgdelta_clone -f "$plan_file" >/dev/null
        ;;
      *)
        echo "Unknown pg-delta transaction mode in self-test: $transaction_mode" >&2
        exit 1
        ;;
    esac
  done < <(jq -r ".files[] | [.transactionMode, .path] | @tsv" '"$TMP"'/pgdelta-plan/envelope.json)
  "$ERPI_AGENT_ENV/bin/agent-env" pg-delta plan --source "$clone_url" --target "$target_url" --out '"$TMP"'/pgdelta-convergence >/dev/null
  "$ERPI_AGENT_ENV/runtime/node/bin/node" -e "const fs=require(\"node:fs\"); const e=JSON.parse(fs.readFileSync(process.argv[1],\"utf8\")); if(e.files.length) { console.error(e); process.exit(1) }" '"$TMP"'/pgdelta-convergence/envelope.json
  after_source="$("$ERPI_AGENT_ENV/bin/agent-env" pg pg_dump --schema-only --no-owner --restrict-key=ERPIAgentEnvSelftest pgdelta_source | sha256sum | cut -d" " -f1)"
  after_target="$("$ERPI_AGENT_ENV/bin/agent-env" pg pg_dump --schema-only --no-owner --restrict-key=ERPIAgentEnvSelftest pgdelta_target | sha256sum | cut -d" " -f1)"
  [[ "$before_source" == "$after_source" && "$before_target" == "$after_target" ]] || { echo "pg-delta plan mutated source or target" >&2; exit 1; }

  "$ERPI_AGENT_ENV/bin/agent-env" pg psql -X -v ON_ERROR_STOP=1 -c "create table selftest_data(id integer primary key, note text); insert into selftest_data values (1, '"'"'ok'"'"');" >/dev/null
  "$ERPI_AGENT_ENV/bin/agent-env" pg pg_dump -Fc -f '"$TMP"'/selftest.dump postgres
  "$ERPI_AGENT_ENV/bin/agent-env" pg createdb selftest_restore
  "$ERPI_AGENT_ENV/bin/agent-env" pg pg_restore -d selftest_restore '"$TMP"'/selftest.dump
  "$ERPI_AGENT_ENV/bin/agent-env" pg psql -X -d selftest_restore -Atc "select note from selftest_data where id=1" | grep -Fx ok >/dev/null
  "$ERPI_AGENT_ENV/bin/agent-env" pg pg_amcheck --install-missing --database=postgres >/dev/null
  "$ERPI_AGENT_ENV/bin/agent-env" pg pgbench -i -s 1 postgres >/dev/null
  "$ERPI_AGENT_ENV/bin/agent-env" pg pgbench -c 2 -j 1 -t 2 postgres >/dev/null
'

# An alternate bootstrap identity allows faithful non-superuser role emulation.
BOOTSTRAP_PORT="$(free_port)"
"$ROOT/bin/agent-env" postgres run --bootstrap-user agent_env_bootstrap --port "$BOOTSTRAP_PORT" -- bash -ceu '
  test "$PGUSER" = agent_env_bootstrap
  test "$DATABASE_URL" = "postgresql://agent_env_bootstrap:postgres@127.0.0.1:${PGPORT}/postgres"
  "$ERPI_AGENT_ENV/bin/agent-env" pg psql -X -v ON_ERROR_STOP=1 -At -F: -c "select current_user, rolsuper::int from pg_roles where rolname=current_user" | grep -Fx "agent_env_bootstrap:1" >/dev/null
  "$ERPI_AGENT_ENV/bin/agent-env" pg psql -X -v ON_ERROR_STOP=1 -c "create role postgres login nosuperuser createrole" >/dev/null
  PGUSER=postgres "$ERPI_AGENT_ENV/bin/agent-env" pg psql -X -v ON_ERROR_STOP=1 -At -F: -c "select rolsuper::int, rolcreaterole::int from pg_roles where rolname=current_user" | grep -Fx "0:1" >/dev/null
  PGUSER=postgres "$ERPI_AGENT_ENV/bin/agent-env" pg psql -X -v ON_ERROR_STOP=1 -c "alter default privileges for role postgres revoke execute on functions from public" >/dev/null
  PGUSER=postgres "$ERPI_AGENT_ENV/bin/agent-env" pg psql -X -v ON_ERROR_STOP=1 -c "create role agent_env_child_role" >/dev/null
  if PGUSER=postgres "$ERPI_AGENT_ENV/bin/agent-env" pg psql -X -v ON_ERROR_STOP=1 -c "create role agent_env_forbidden_superuser superuser" >/dev/null 2>&1; then
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
python - <<'PY' "$POSTGREST_REJECT_PORT" "$POSTGREST_PG_PORT" "$POSTGREST_HTTP_PORT" "$POSTGREST_SIGNAL_PORT" "$PG_PORT" "$BOOTSTRAP_PORT" "$NONZERO_PORT" "$SIGNAL_PORT"
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
