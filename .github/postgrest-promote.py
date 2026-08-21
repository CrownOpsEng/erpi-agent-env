#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, text: str) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text, encoding="utf-8")


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one anchor, found {count}: {old[:120]!r}")
    write(path, text.replace(old, new, 1))


def replace_count(path: str, old: str, new: str, expected: int) -> None:
    text = read(path)
    count = text.count(old)
    if count != expected:
        raise SystemExit(f"{path}: expected {expected} anchors, found {count}: {old[:120]!r}")
    write(path, text.replace(old, new))


# Exact version/provenance pin. Supabase CLI 2.114.0 selects upstream PostgREST
# 14.16 and the official linux-static-x86-64 asset for Linux x64.
replace_once(
    "versions.env",
    'PG_DELTA_SUPABASE_CLI_BASELINE="2.114.0"\n',
    'PG_DELTA_SUPABASE_CLI_BASELINE="2.114.0"\n\n'
    'POSTGREST_VERSION="14.16"\n'
    'POSTGREST_SHA256="36b8ae140f188cfcd6003494805bf35a41e895f88c12be9183d60f91782145c6"\n'
    'POSTGREST_SUPABASE_CLI_BASELINE="2.114.0"\n',
)

postgrest_py = r'''#!/usr/bin/env python3
from __future__ import annotations

import argparse
import http.client
import os
import pathlib
import shutil
import signal
import socket
import subprocess
import sys
import time
import uuid
from urllib.parse import parse_qsl, urlsplit

ROOT = pathlib.Path(__file__).resolve().parents[1]
BINARY = ROOT / "runtime/postgrest/postgrest"
STATE = ROOT / "state/postgrest"
LOOPBACK_HOSTS = {"127.0.0.1", "::1"}
RETARGET_QUERY_KEYS = {"host", "hostaddr", "service", "servicefile"}


def validate_db_uri(uri: str) -> None:
    parsed = urlsplit(uri)
    if parsed.scheme not in {"postgres", "postgresql"}:
        raise SystemExit("PostgREST database URI must use postgres:// or postgresql://.")
    if parsed.hostname not in LOOPBACK_HOSTS:
        raise SystemExit("PostgREST database target must use numeric loopback (127.0.0.1 or ::1).")
    for key, _value in parse_qsl(parsed.query, keep_blank_values=True):
        if key.lower() in RETARGET_QUERY_KEYS:
            raise SystemExit(f"PostgREST database URI query parameter {key!r} can retarget the connection and is refused.")


def free_on_loopback(port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            sock.bind(("127.0.0.1", port))
            return True
        except OSError:
            return False


def server_env(args: argparse.Namespace) -> dict[str, str]:
    env = dict(os.environ)
    for key in list(env):
        if key.startswith("PGRST_"):
            env.pop(key, None)
    env.update(
        {
            "PGRST_DB_URI": args.db_uri,
            "PGRST_DB_SCHEMAS": args.db_schemas,
            "PGRST_DB_ANON_ROLE": args.db_anon_role,
            "PGRST_SERVER_HOST": "127.0.0.1",
            "PGRST_SERVER_PORT": str(args.port),
        }
    )
    if args.db_extra_search_path is not None:
        env["PGRST_DB_EXTRA_SEARCH_PATH"] = args.db_extra_search_path
    if args.db_pre_request is not None:
        env["PGRST_DB_PRE_REQUEST"] = args.db_pre_request
    return env


def wait_ready(process: subprocess.Popen[bytes], port: int, log: pathlib.Path) -> None:
    deadline = time.monotonic() + 15.0
    last_error = ""
    while time.monotonic() < deadline:
        rc = process.poll()
        if rc is not None:
            text = log.read_text(encoding="utf-8", errors="replace") if log.is_file() else ""
            if text:
                sys.stderr.write("\n--- PostgREST startup log ---\n" + text)
                if not text.endswith("\n"):
                    sys.stderr.write("\n")
                sys.stderr.write("--- end PostgREST startup log ---\n")
            raise SystemExit(f"Bundled PostgREST exited during startup (exit {rc}).")
        try:
            conn = http.client.HTTPConnection("127.0.0.1", port, timeout=0.25)
            conn.request("GET", "/")
            response = conn.getresponse()
            response.read()
            conn.close()
            if response.status != 503:
                return
            last_error = "HTTP 503 while schema cache initializes"
        except (OSError, http.client.HTTPException) as exc:
            last_error = str(exc)
        time.sleep(0.05)
    text = log.read_text(encoding="utf-8", errors="replace") if log.is_file() else ""
    if text:
        sys.stderr.write("\n--- PostgREST startup log ---\n" + text)
        if not text.endswith("\n"):
            sys.stderr.write("\n")
        sys.stderr.write("--- end PostgREST startup log ---\n")
    raise SystemExit(f"Bundled PostgREST did not become ready on loopback: {last_error}")


def terminate(process: subprocess.Popen[bytes] | None) -> None:
    if process is None or process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()


def main() -> int:
    parser = argparse.ArgumentParser(description="Run one command against a bounded local PostgREST process.")
    parser.add_argument("--db-uri", required=True)
    parser.add_argument("--db-schemas", required=True)
    parser.add_argument("--db-anon-role", required=True)
    parser.add_argument("--db-extra-search-path")
    parser.add_argument("--db-pre-request")
    parser.add_argument("--port", type=int, default=3000)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.command and args.command[0] == "--":
        args.command = args.command[1:]
    if not args.command:
        parser.error("a command is required after --")
    if not (1 <= args.port <= 65535):
        parser.error("--port must be 1..65535")
    validate_db_uri(args.db_uri)
    if not free_on_loopback(args.port):
        raise SystemExit(f"127.0.0.1:{args.port} is already in use; refusing to target or replace an unknown HTTP service.")
    if not BINARY.is_file() or not os.access(BINARY, os.X_OK):
        raise SystemExit(f"Bundled PostgREST executable missing: {BINARY}")

    STATE.mkdir(parents=True, exist_ok=True)
    run_state = STATE / f"run-{uuid.uuid4().hex}"
    run_state.mkdir(mode=0o700)
    log = run_state / "postgrest.log"
    server: subprocess.Popen[bytes] | None = None
    child: subprocess.Popen[bytes] | None = None
    old_handlers: dict[int, object] = {}

    def forward(sig: int, _frame) -> None:
        if child is not None and child.poll() is None:
            child.send_signal(sig)

    try:
        with log.open("wb") as handle:
            server = subprocess.Popen([str(BINARY)], env=server_env(args), stdout=handle, stderr=subprocess.STDOUT)
        wait_ready(server, args.port, log)

        for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
            old_handlers[sig] = signal.getsignal(sig)
            signal.signal(sig, forward)

        child_env = dict(os.environ)
        for key in list(child_env):
            if key.startswith("PGRST_"):
                child_env.pop(key, None)
        child_env.update(
            {
                "POSTGREST_URL": f"http://127.0.0.1:{args.port}",
                "POSTGREST_HOST": "127.0.0.1",
                "POSTGREST_PORT": str(args.port),
                "MAGNET_AGENT_POSTGREST": "1",
            }
        )
        child = subprocess.Popen(args.command, env=child_env)
        while True:
            rc = child.poll()
            if rc is not None:
                child = None
                return rc
            server_rc = server.poll()
            if server_rc is not None:
                terminate(child)
                child = None
                text = log.read_text(encoding="utf-8", errors="replace") if log.is_file() else ""
                if text:
                    sys.stderr.write("\n--- PostgREST runtime log ---\n" + text)
                    if not text.endswith("\n"):
                        sys.stderr.write("\n")
                    sys.stderr.write("--- end PostgREST runtime log ---\n")
                raise SystemExit(f"Bundled PostgREST exited while the child command was running (exit {server_rc}).")
            time.sleep(0.05)
    finally:
        for sig, handler in old_handlers.items():
            signal.signal(sig, handler)
        terminate(child)
        terminate(server)
        shutil.rmtree(run_state, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
'''
write("templates/scripts/postgrest.py", postgrest_py)

license_text = '''Copyright (c) 2014 Joe Nelson
Copyright (c) 2019 Steve Chavez

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
'''
write("vendor/postgrest/LICENSE", license_text)

# Builder payload/provenance and runtime control surface.
replace_once(
    "build.sh",
    '"$BUILD/runtime/postgres/client" "$BUILD/runtime/node-capsules" "$BUILD/runtime/pg-delta" "$BUILD/env"',
    '"$BUILD/runtime/postgres/client" "$BUILD/runtime/node-capsules" "$BUILD/runtime/pg-delta" "$BUILD/runtime/postgrest" "$BUILD/env"',
)
replace_once(
    "build.sh",
    '"$BUILD/licenses/third-party" "$BUILD/licenses/postgresql" "$BUILD/licenses/pg-delta" \\\n',
    '"$BUILD/licenses/third-party" "$BUILD/licenses/postgresql" "$BUILD/licenses/pg-delta" "$BUILD/licenses/postgrest" \\\n',
)
replace_count(
    "build.sh",
    '"$BUILD/state/npm-global" "$BUILD/state/pycache" "$BUILD/state/postgres"',
    '"$BUILD/state/npm-global" "$BUILD/state/pycache" "$BUILD/state/postgres" "$BUILD/state/postgrest"',
    2,
)
replace_once(
    "build.sh",
    '    "$BUILD/state/pycache" \\\n    "$BUILD/state/postgres"\n',
    '    "$BUILD/state/pycache" \\\n    "$BUILD/state/postgres" \\\n    "$BUILD/state/postgrest"\n',
)
replace_once(
    "build.sh",
    'extract_single "$MILLER_AR" mlr "$BUILD/bin/mlr"\n\nlog "PostgreSQL $POSTGRES_VERSION from pinned official source"',
    'extract_single "$MILLER_AR" mlr "$BUILD/bin/mlr"\n\n'
    'log "PostgREST $POSTGREST_VERSION"\n'
    'POSTGREST_AR="$DL/postgrest-v${POSTGREST_VERSION}-linux-static-x86-64.tar.xz"\n'
    'fetch "https://github.com/PostgREST/postgrest/releases/download/v${POSTGREST_VERSION}/postgrest-v${POSTGREST_VERSION}-linux-static-x86-64.tar.xz" "$POSTGREST_AR"\n'
    'verify_one "$POSTGREST_AR" "$POSTGREST_SHA256"\n'
    'extract_single "$POSTGREST_AR" postgrest "$BUILD/runtime/postgrest/postgrest"\n'
    '"$BUILD/runtime/postgrest/postgrest" --version | grep -Fx "PostgREST $POSTGREST_VERSION" >/dev/null\n'
    'file "$BUILD/runtime/postgrest/postgrest" | grep -F "statically linked" >/dev/null\n'
    'install -m 0644 "$SELF_DIR/vendor/postgrest/LICENSE" "$BUILD/licenses/postgrest/LICENSE"\n\n'
    'log "PostgreSQL $POSTGRES_VERSION from pinned official source"',
)
replace_once(
    "build.sh",
    'cp "$SELF_DIR/templates/scripts/postgres.py" "$BUILD/scripts/postgres.py"\n',
    'cp "$SELF_DIR/templates/scripts/postgres.py" "$BUILD/scripts/postgres.py"\n'
    'cp "$SELF_DIR/templates/scripts/postgrest.py" "$BUILD/scripts/postgrest.py"\n',
)
replace_once(
    "build.sh",
    '"$BUILD/scripts/capabilities.py" "$BUILD/scripts/postgres.py" "$BUILD/scripts/pgtap.py"',
    '"$BUILD/scripts/capabilities.py" "$BUILD/scripts/postgres.py" "$BUILD/scripts/postgrest.py" "$BUILD/scripts/pgtap.py"',
)
replace_once(
    "build.sh",
    '    "pg_delta": {"version": "$PG_DELTA_VERSION", "supabase_cli_baseline": "$PG_DELTA_SUPABASE_CLI_BASELINE", "surface": "plan-only", "live_connections": "numeric-loopback-only"},\n',
    '    "pg_delta": {"version": "$PG_DELTA_VERSION", "supabase_cli_baseline": "$PG_DELTA_SUPABASE_CLI_BASELINE", "surface": "plan-only", "live_connections": "numeric-loopback-only"},\n'
    '    "postgrest": {"version": "$POSTGREST_VERSION", "supabase_cli_baseline": "$POSTGREST_SUPABASE_CLI_BASELINE", "database_targets": "numeric-loopback-only", "http_listener": "loopback-only"},\n',
)
replace_once(
    "build.sh",
    'source_row miller "$MILLER_VERSION" "https://github.com/johnkerl/miller/releases/download/v$MILLER_VERSION/miller-$MILLER_VERSION-linux-amd64.tar.gz" "$MILLER_SHA256"\n',
    'source_row miller "$MILLER_VERSION" "https://github.com/johnkerl/miller/releases/download/v$MILLER_VERSION/miller-$MILLER_VERSION-linux-amd64.tar.gz" "$MILLER_SHA256"\n'
    'source_row postgrest "$POSTGREST_VERSION" "https://github.com/PostgREST/postgrest/releases/download/v$POSTGREST_VERSION/postgrest-v$POSTGREST_VERSION-linux-static-x86-64.tar.xz" "$POSTGREST_SHA256"\n',
)

# Cheap runtime discovery and bounded runner routing.
replace_once(
    "templates/bin/agent-env",
    '"$PYTHONPYCACHEPREFIX" "$ROOT/state/postgres" 2>/dev/null || true',
    '"$PYTHONPYCACHEPREFIX" "$ROOT/state/postgres" "$ROOT/state/postgrest" 2>/dev/null || true',
)
replace_once(
    "templates/bin/agent-env",
    '  pgtap FILE...            Run pgTAP SQL files with strict TAP accounting\n  pg-delta plan [...]      Generate a local-only PostgreSQL schema migration plan\n',
    '  pgtap FILE...            Run pgTAP SQL files with strict TAP accounting\n'
    '  postgrest run [...] -- C Run one command against bounded local PostgREST\n'
    '  pg-delta plan [...]      Generate a local-only PostgreSQL schema migration plan\n',
)
replace_once(
    "templates/bin/agent-env",
    '  pgtap) shift; exec "$ROOT/env/bin/python" "$ROOT/scripts/pgtap.py" "$@" ;;\n  pg-delta)\n',
    '  pgtap) shift; exec "$ROOT/env/bin/python" "$ROOT/scripts/pgtap.py" "$@" ;;\n'
    '  postgrest)\n'
    '    shift\n'
    '    sub="${1:-}"\n'
    '    [[ "$sub" == run ]] || { echo "Usage: agent-env postgrest run --db-uri postgresql://... --db-schemas SCHEMAS --db-anon-role ROLE [--db-extra-search-path PATH] [--db-pre-request FUNCTION] [--port N] -- COMMAND" >&2; exit 2; }\n'
    '    shift\n'
    '    exec "$ROOT/env/bin/python" "$ROOT/scripts/postgrest.py" "$@"\n'
    '    ;;\n'
    '  pg-delta)\n',
)

# Runtime operating reference: enough detail to use the capability without
# turning the root agent router into a service manual.
replace_once(
    "templates/RUNTIME-README.md",
    'The runtime includes pgTAP 1.3.3, plpgsql_check 2.8.11, pgbench, pg_dump/pg_restore, pg_amcheck, pg_checksums and normal client helpers. Project-specific compatibility roles, migrations, fixture data, test expectations, and production credentials do not belong in this bundle.\n\n### pg-delta planning\n',
    'The runtime includes pgTAP 1.3.3, plpgsql_check 2.8.11, pgbench, pg_dump/pg_restore, pg_amcheck, pg_checksums and normal client helpers. Project-specific compatibility roles, migrations, fixture data, test expectations, and production credentials do not belong in this bundle.\n\n'
    '### PostgREST request execution\n\n'
    '`agent-env postgrest run --db-uri postgresql://authenticator@127.0.0.1:54322/postgres --db-schemas api --db-anon-role anon --port 3000 -- COMMAND` starts the pinned standalone PostgREST 14.16 process, waits for its schema cache to become ready, exports `POSTGREST_URL` to `COMMAND`, and tears the service down when that command exits. The version is the exact upstream native default selected by the qualified Supabase CLI 2.114.0 baseline.\n\n'
    'Database URLs are restricted to numeric loopback and query parameters capable of retargeting libpq are refused. HTTP is always bound to `127.0.0.1`; inherited `PGRST_*` variables are scrubbed before the service starts. Optional `--db-extra-search-path` and `--db-pre-request` values are repository-owned PostgREST configuration, not provider policy. This surface is for real PostgREST request-role, transaction, search-path, pre-request and RPC semantics. It deliberately does not emulate Kong, Supabase Auth/API-key routing, Storage, or managed-platform behavior.\n\n'
    '### pg-delta planning\n',
)

# Third-party inventory and builder-level capability/boundary description.
replace_once(
    "templates/THIRD-PARTY.md",
    'Direct third-party license and attribution texts for the redistributed command/database/capsule components are included under `licenses/third-party/`. ShellCheck 0.11.0 is GPL-3.0-only;',
    'Direct third-party license and attribution texts for the redistributed command/database/capsule components are included under `licenses/third-party/`, with the directly pinned PostgREST license under `licenses/postgrest/`. ShellCheck 0.11.0 is GPL-3.0-only;',
)
replace_once(
    "templates/THIRD-PARTY.md",
    '- plpgsql_check 2.8.11 — MIT-style license.\n- `@supabase/pg-delta`',
    '- plpgsql_check 2.8.11 — MIT-style license.\n- PostgREST 14.16 — MIT.\n- `@supabase/pg-delta`',
)
replace_once(
    "README.md",
    '- PostgreSQL 17.10 server plus explicitly routed client/test/recovery tools, pgTAP 1.3.3, and plpgsql_check 2.8.11\n- a plan-only `@supabase/pg-delta`',
    '- PostgreSQL 17.10 server plus explicitly routed client/test/recovery tools, pgTAP 1.3.3, and plpgsql_check 2.8.11\n'
    '- PostgREST 14.16 as the exact official static Linux x64 native default selected by Supabase CLI 2.114.0, exposed only through a loopback-only local execution wrapper\n'
    '- a plan-only `@supabase/pg-delta`',
)
replace_once(
    "README.md",
    'Supabase CLI and project-specific Supabase tooling, application frameworks, project test frameworks, Git, Make, and Docker/Podman remain project/host concerns unless a future demonstrated need earns promotion.',
    'The full Supabase CLI/stack, Kong, Auth, Storage, project-specific Supabase tooling, application frameworks, project test frameworks, Git, Make, and Docker/Podman remain project/host concerns. Standalone PostgREST is promoted only as the generic HTTP-to-PostgreSQL request-semantics discriminator; it is not managed Supabase parity.',
)
replace_once(
    "README.md",
    'exercises pgTAP failure handling, plpgsql_check, pg-delta source→target→clone convergence and remote-target refusal, dump/restore, pg_amcheck, pgbench, child-exit propagation and signal cleanup;',
    'exercises pgTAP failure handling, plpgsql_check, pg-delta source→target→clone convergence and remote-target refusal, real PostgREST role impersonation/pre-request/RPC privilege behavior plus remote-target refusal and signal cleanup, dump/restore, pg_amcheck, pgbench, child-exit propagation and signal cleanup;',
)

# Stable validation authority.
replace_once(
    "VALIDATION.md",
    '- exact pg-delta lock/API installation, plan-only routing, numeric-loopback refusal boundary, representative source→target→clone convergence, managed-schema filtering, and empty convergence re-plan\n',
    '- exact pg-delta lock/API installation, plan-only routing, numeric-loopback refusal boundary, representative source→target→clone convergence, managed-schema filtering, and empty convergence re-plan\n'
    '- exact PostgREST upstream asset/version/static-binary provenance, numeric-loopback database refusal, loopback-only HTTP binding, real request-role impersonation/search-path/pre-request semantics, SECURITY DEFINER→SECURITY INVOKER success and SQLSTATE `42501` negative behavior over HTTP, plus interrupted-process cleanup\n',
)
replace_once(
    "VALIDATION.md",
    '## Project promotion proof\n',
    '## PostgREST compatibility boundary\n\n'
    'PostgREST 14.16 is pinned because it is the exact upstream native default selected for Linux x64 by the qualified Supabase CLI 2.114.0 baseline. The environment exposes only a bounded local execution surface: database URLs must remain numeric loopback, the HTTP listener is fixed to loopback, inherited `PGRST_*` configuration is scrubbed, and project-supplied schemas, roles, pre-request functions and RPCs remain target-repository state.\n\n'
    'Acceptance must exercise the real PostgREST process rather than replacing it with `SET ROLE` or direct SQL. It proves request-role/session-role context, request search path, a configured generic pre-request function, and a SECURITY DEFINER wrapper calling a SECURITY INVOKER dependency in both a correctly granted path and a deliberately missing-schema-privilege path that surfaces SQLSTATE `42501` over HTTP. It also proves remote database refusal and signal cleanup.\n\n'
    'This capability is a discriminator for ordinary PostgREST semantics, not a claim of managed Supabase parity. Kong routing, Supabase Auth/API keys, Storage, Realtime and other provider topology remain outside the bundle. A PostgREST version or compatibility-baseline change requires fresh upstream-asset and runtime qualification before promotion.\n\n'
    '## Project promotion proof\n',
)

# Source/static gates for exact pin, boundary and newly required runtime files.
replace_once(
    "tests/static-check.sh",
    'templates/scripts/postgres.py templates/scripts/pgtap.py',
    'templates/scripts/postgres.py templates/scripts/postgrest.py templates/scripts/pgtap.py',
)
replace_once(
    "tests/static-check.sh",
    'vendor/pg-delta/package-lock.json vendor/pg-delta/LICENSE templates/scripts/pg-delta.mjs',
    'vendor/pg-delta/package-lock.json vendor/pg-delta/LICENSE vendor/postgrest/LICENSE templates/scripts/pg-delta.mjs',
)
replace_once(
    "tests/static-check.sh",
    '# The v1 Python lock is source-controlled input, not resolved during hydration.\n',
    '# Standalone PostgREST is an exact upstream static asset with bounded local routing.\n'
    'grep -F \'POSTGREST_VERSION="14.16"\' "$ROOT/versions.env" >/dev/null\n'
    'grep -F \'POSTGREST_SHA256="36b8ae140f188cfcd6003494805bf35a41e895f88c12be9183d60f91782145c6"\' "$ROOT/versions.env" >/dev/null\n'
    'grep -F \'POSTGREST_SUPABASE_CLI_BASELINE="2.114.0"\' "$ROOT/versions.env" >/dev/null\n'
    'grep -F \'postgrest-v${POSTGREST_VERSION}-linux-static-x86-64.tar.xz\' "$ROOT/build.sh" >/dev/null\n'
    'grep -F \'verify_one "$POSTGREST_AR" "$POSTGREST_SHA256"\' "$ROOT/build.sh" >/dev/null\n'
    'grep -F \'PGRST_SERVER_HOST\' "$ROOT/templates/scripts/postgrest.py" >/dev/null\n'
    'grep -F \'RETARGET_QUERY_KEYS\' "$ROOT/templates/scripts/postgrest.py" >/dev/null\n'
    'grep -F \'postgrest run\' "$ROOT/templates/bin/agent-env" >/dev/null\n'
    '# The v1 Python lock is source-controlled input, not resolved during hydration.\n',
)

# Runtime self-test metadata and executable probe.
replace_once(
    "templates/scripts/selftest.sh",
    "assert {'python-build-standalone','postgres-server-source','postgres-server-build-image','postgres-server-build-flex','node-postgres','pgls-wasm','pg-delta-lock'} <= components\n",
    "assert {'python-build-standalone','postgres-server-source','postgres-server-build-image','postgres-server-build-flex','postgrest','node-postgres','pgls-wasm','pg-delta-lock'} <= components\n",
)
replace_once(
    "templates/scripts/selftest.sh",
    "assert (root/'licenses/pg-delta/LICENSE').is_file()\n",
    "assert (root/'licenses/pg-delta/LICENSE').is_file()\n"
    "postgrest=env['capabilities']['postgrest']\n"
    "assert postgrest=={'version':'14.16','supabase_cli_baseline':'2.114.0','database_targets':'numeric-loopback-only','http_listener':'loopback-only'},postgrest\n"
    "assert (root/'licenses/postgrest/LICENSE').is_file()\n",
)
replace_once(
    "templates/scripts/selftest.sh",
    "mlr --version | grep -F '6.20.2' >/dev/null\n",
    "mlr --version | grep -F '6.20.2' >/dev/null\n"
    '"$ROOT/runtime/postgrest/postgrest" --version | grep -Fx \'PostgREST 14.16\' >/dev/null\n',
)

postgrest_selftest = r'''# PostgREST refuses remote database targeting before starting a service.
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
  "$MAGNET_AGENT_ENV/bin/agent-env" pg psql -X -v ON_ERROR_STOP=1 -f "$POSTGREST_FIXTURE" >/dev/null
  db_uri="postgresql://authenticator@127.0.0.1:${PGPORT}/postgres"
  "$MAGNET_AGENT_ENV/bin/agent-env" postgrest run \
    --db-uri "$db_uri" --db-schemas api --db-anon-role anon \
    --db-pre-request api.pre_request --port "$POSTGREST_HTTP_PORT" -- \
    python "$POSTGREST_PROBE"
  "$MAGNET_AGENT_ENV/bin/agent-env" pg psql -X -Atc "select label from core.events order by label" | grep -Fx ok >/dev/null

  POSTGREST_SIGNAL_READY="$POSTGREST_SIGNAL_READY" \
  "$MAGNET_AGENT_ENV/bin/agent-env" postgrest run \
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

'''
replace_once(
    "templates/scripts/selftest.sh",
    'PG_PORT="$(free_port)"\n',
    postgrest_selftest + 'PG_PORT="$(free_port)"\n',
)
replace_once(
    "templates/scripts/selftest.sh",
    'python - <<\'PY\' "$PG_PORT" "$BOOTSTRAP_PORT" "$NONZERO_PORT" "$SIGNAL_PORT"\n',
    'python - <<\'PY\' "$POSTGREST_REJECT_PORT" "$POSTGREST_PG_PORT" "$POSTGREST_HTTP_PORT" "$POSTGREST_SIGNAL_PORT" "$PG_PORT" "$BOOTSTRAP_PORT" "$NONZERO_PORT" "$SIGNAL_PORT"\n',
)

# Remove temporary qualification machinery from the target tree before the
# repository-owned source gate/build are run. The currently executing workflow
# remains loaded by Actions; these deletions only affect the eventual tree.
for rel in (".github/workflows/postgrest-qualify.yml", ".github/postgrest-promote.py"):
    path = ROOT / rel
    if path.exists():
        path.unlink()

print("PostgREST promotion source transformation complete.")
