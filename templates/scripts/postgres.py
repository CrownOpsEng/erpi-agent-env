#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import pathlib
import pwd
import shutil
import signal
import socket
import subprocess
import sys
import time
import uuid
from urllib.parse import quote

ROOT = pathlib.Path(__file__).resolve().parents[1]
SERVER = ROOT / "runtime/postgres/server"
CLIENT = ROOT / "runtime/postgres/client"
STATE = ROOT / "state/postgres"

DB_ENV_KEYS = {
    "DATABASE_URL", "PGHOST", "PGHOSTADDR", "PGPORT", "PGDATABASE", "PGUSER",
    "PGPASSWORD", "PGPASSFILE", "PGSERVICE", "PGSERVICEFILE", "PGOPTIONS",
    "PGAPPNAME", "PGCONNECT_TIMEOUT", "PGCHANNELBINDING", "PGSSLMODE", "PGSSLROOTCERT",
    "PGSSLCERT", "PGSSLKEY", "PGREQUIRESSL", "PGTARGETSESSIONATTRS",
}


def run_as(uid: int | None, gid: int | None):
    if uid is None:
        return None
    def preexec() -> None:
        os.setgroups([])
        os.setgid(gid if gid is not None else uid)
        os.setuid(uid)
    return preexec


def free_on_loopback(port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            s.bind(("127.0.0.1", port))
            return True
        except OSError:
            return False


def client_env(base: dict[str, str] | None = None) -> dict[str, str]:
    env = dict(base or os.environ)
    runtime_libs = [str(CLIENT / "lib"), str(SERVER / "lib")]
    existing = env.get("LD_LIBRARY_PATH", "")
    if existing:
        runtime_libs.append(existing)
    env["LD_LIBRARY_PATH"] = ":".join(runtime_libs)
    return env


def command_env(port: int, bootstrap_user: str) -> dict[str, str]:
    env = dict(os.environ)
    for key in DB_ENV_KEYS:
        env.pop(key, None)
    env.update({
        "PGHOST": "127.0.0.1",
        "PGPORT": str(port),
        "PGDATABASE": "postgres",
        "PGUSER": bootstrap_user,
        "DATABASE_URL": f"postgresql://{quote(bootstrap_user, safe='')}:postgres@127.0.0.1:{port}/postgres",
        "MAGNET_AGENT_POSTGRES": "1",
    })
    return client_env(env)


def pg_bin(name: str) -> pathlib.Path:
    path = SERVER / "bin" / name
    if not path.is_file():
        raise SystemExit(f"Bundled PostgreSQL server tool missing: {path}")
    return path


def client_bin(name: str) -> pathlib.Path:
    path = CLIENT / "bin" / name
    if not path.is_file():
        raise SystemExit(f"Bundled PostgreSQL client tool missing: {path}")
    return path


def main() -> int:
    parser = argparse.ArgumentParser(description="Run one command against a disposable bundled PostgreSQL cluster.")
    parser.add_argument("--port", type=int, default=54322)
    parser.add_argument("--keep", action="store_true", help="Preserve the disposable cluster for debugging.")
    parser.add_argument("--bootstrap-user", default="postgres", help="Bootstrap superuser role name (default: postgres).")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.command and args.command[0] == "--":
        args.command = args.command[1:]
    if not args.command:
        parser.error("a command is required after --")
    if not (1 <= args.port <= 65535):
        parser.error("--port must be 1..65535")
    if not args.bootstrap_user:
        parser.error("--bootstrap-user must not be empty")
    if not free_on_loopback(args.port):
        raise SystemExit(f"127.0.0.1:{args.port} is already in use; refusing to target an unknown PostgreSQL server.")

    STATE.mkdir(parents=True, exist_ok=True)
    cluster = STATE / f"cluster-{uuid.uuid4().hex}"
    data = cluster / "data"
    log = cluster / "postgres.log"
    cluster.mkdir(mode=0o700)

    uid = gid = None
    if os.geteuid() == 0:
        nobody = pwd.getpwnam("nobody")
        uid, gid = nobody.pw_uid, nobody.pw_gid
        os.chown(cluster, uid, gid)

    preexec = run_as(uid, gid)
    init = [str(pg_bin("initdb")), "-D", str(data), "--encoding=UTF8", "--locale=C.utf8", "--data-checksums", f"--username={args.bootstrap_user}", "--auth-local=trust", "--auth-host=trust"]
    subprocess.run(init, check=True, env=client_env(), preexec_fn=preexec, stdout=subprocess.DEVNULL)

    config = data / "postgresql.conf"
    with config.open("a", encoding="utf-8") as f:
        f.write("\nlisten_addresses = '127.0.0.1'\n")
        f.write(f"port = {args.port}\n")
        f.write("unix_socket_directories = ''\n")
        f.write("jit = off\n")
        f.write("compute_query_id = auto\n")
        f.write("max_connections = 60\n")
        f.write("timezone = 'UTC'\n")
        f.write("log_min_messages = warning\n")

    pg_ctl = str(pg_bin("pg_ctl"))
    server_started = False
    child: subprocess.Popen[bytes] | None = None
    old_handlers: dict[int, object] = {}

    def forward(sig: int, _frame) -> None:
        if child is not None and child.poll() is None:
            child.send_signal(sig)

    try:
        start = subprocess.run(
            [pg_ctl, "-D", str(data), "-l", str(log), "-w", "start"],
            check=False,
            env=client_env(),
            preexec_fn=preexec,
            stdout=subprocess.DEVNULL,
        )
        if start.returncode != 0:
            if log.is_file():
                log_text = log.read_text(encoding="utf-8", errors="replace")
                sys.stderr.write("\n--- PostgreSQL startup log ---\n")
                sys.stderr.write(log_text)
                if not log_text.endswith("\n"):
                    sys.stderr.write("\n")
                sys.stderr.write("--- end PostgreSQL startup log ---\n")
            raise SystemExit(f"Bundled PostgreSQL failed to start (pg_ctl exit {start.returncode}).")
        server_started = True
        ready_env = command_env(args.port, args.bootstrap_user)
        subprocess.run([str(client_bin("pg_isready")), "-q"], check=True, env=ready_env)

        for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
            old_handlers[sig] = signal.getsignal(sig)
            signal.signal(sig, forward)

        child = subprocess.Popen(args.command, env=command_env(args.port, args.bootstrap_user))
        rc = child.wait()
        child = None
        return rc
    finally:
        for sig, handler in old_handlers.items():
            signal.signal(sig, handler)
        if child is not None and child.poll() is None:
            child.terminate()
            try:
                child.wait(timeout=5)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()
        if server_started:
            subprocess.run([pg_ctl, "-D", str(data), "-m", "fast", "-w", "stop"], env=client_env(), preexec_fn=preexec, stdout=subprocess.DEVNULL, check=False)
            checksums = client_bin("pg_checksums")
            result = subprocess.run([str(checksums), "--check", "-D", str(data)], env=client_env(), stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            if result.returncode != 0:
                sys.stderr.write(result.stdout)
                raise SystemExit("PostgreSQL checksum verification failed after shutdown.")
        if args.keep:
            print(f"Preserved PostgreSQL cluster: {cluster}", file=sys.stderr)
        else:
            shutil.rmtree(cluster, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
