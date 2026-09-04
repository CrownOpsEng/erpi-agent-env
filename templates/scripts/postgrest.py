#!/usr/bin/env python3
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
                "ERPI_AGENT_POSTGREST": "1",
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
