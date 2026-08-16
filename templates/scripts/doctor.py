#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import pathlib
import platform
import shutil
import subprocess
import sys
from typing import Any

ROOT = pathlib.Path(__file__).resolve().parents[1]

def run(args: list[str], timeout: int = 6) -> tuple[int, str]:
    try:
        p = subprocess.run(args, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout, check=False)
        return p.returncode, p.stdout.strip()
    except (OSError, subprocess.TimeoutExpired) as exc:
        return 127, str(exc)

def version(command: str, args: list[str] | None = None) -> dict[str, Any]:
    path = shutil.which(command)
    if not path:
        return {"available": False}
    rc, output = run([path, *(args or ["--version"])])
    return {"available": rc == 0, "path": path, "version": output.splitlines()[0] if output else "", "returncode": rc}

def git_root() -> pathlib.Path | None:
    if not shutil.which("git"):
        return None
    rc, out = run(["git", "rev-parse", "--show-toplevel"])
    return pathlib.Path(out).resolve() if rc == 0 and out else None

def main() -> int:
    parser = argparse.ArgumentParser(description="Diagnose the portable Magnet agent environment and current repository.")
    parser.add_argument("--json", action="store_true")
    ns = parser.parse_args()

    libc_name, libc_version = platform.libc_ver()
    data: dict[str, Any] = {
        "environment": {
            "root": str(ROOT),
            "target": "linux-x86_64-gnu",
            "platform": platform.system(),
            "machine": platform.machine(),
            "libc": f"{libc_name} {libc_version}".strip(),
            "python": platform.python_version(),
            "python_executable": sys.executable,
            "python_prefix": sys.prefix,
            "python_base_prefix": sys.base_prefix,
            "state_writable": os.access(ROOT / "state", os.W_OK),
        },
        "bundled_tools": {},
        "host_commands": {},
        "repository": {},
    }
    for tool, args in {
        "uv": ["--version"], "gh": ["--version"], "node": ["--version"], "npm": ["--version"],
        "jq": ["--version"], "yq": ["--version"], "rg": ["--version"],
        "actionlint": ["--version"], "gitleaks": ["version"], "pytest": ["--version"],
    }.items():
        data["bundled_tools"][tool] = version(tool, args)
    for tool in ("git", "make", "docker", "podman", "shellcheck", "curl", "sha256sum", "find", "cmp", "diff"):
        data["host_commands"][tool] = version(tool, ["--version"])

    root = git_root()
    if root:
        repo: dict[str, Any] = {"root": str(root)}
        node_version_file = root / ".node-version"
        if node_version_file.is_file():
            expected = node_version_file.read_text(encoding="utf-8").strip()
            actual = platform_node_major()
            repo["node_expected_major"] = expected
            repo["node_actual_major"] = actual
            repo["node_matches"] = actual == expected
        supabase = root / "node_modules/.bin/supabase"
        repo["repo_supabase_installed"] = supabase.exists()
        if supabase.exists() and os.access(supabase, os.X_OK):
            rc, out = run([str(supabase), "--version"])
            repo["repo_supabase_version"] = out.splitlines()[0] if rc == 0 and out else None
        makefile = root / "Makefile"
        repo["makefile_present"] = makefile.is_file()
        repo["magnet_photos_detected"] = (root / "AGENTS.md").is_file() and "Magnet Photos" in (root / "AGENTS.md").read_text(encoding="utf-8", errors="ignore")[:2000]
        data["repository"] = repo

    if ns.json:
        print(json.dumps(data, indent=2, sort_keys=True))
    else:
        env = data["environment"]
        print(f"Magnet Agent Environment: {env['root']}")
        print(f"Target: {env['platform']} {env['machine']} | {env['libc']}")
        print(f"Python: {env['python']} | prefix={env['python_prefix']}")
        print(f"Mutable state: {'✓ writable' if env['state_writable'] else '✗ not writable'}")
        print("\nBundled tools")
        for name, info in data["bundled_tools"].items():
            mark = "✓" if info.get("available") else "✗"
            print(f"  {mark} {name:<11} {info.get('version','')}")
        print("\nHost commands")
        for name, info in data["host_commands"].items():
            mark = "✓" if info.get("available") else "○"
            print(f"  {mark} {name:<11} {info.get('version','')}")
        if data["repository"]:
            repo = data["repository"]
            print(f"\nRepository: {repo['root']}")
            if "node_expected_major" in repo:
                mark = "✓" if repo["node_matches"] else "✗"
                print(f"  {mark} Node major {repo['node_actual_major']} (repo expects {repo['node_expected_major']})")
            if repo.get("magnet_photos_detected"):
                print("  ✓ Magnet Photos repository detected")
                print("  Repository tooling remains authoritative: use make help / make doctor / make check-fast.")
                print("  Full database checks still require a working Docker/Podman-compatible runtime.")
    required = [v for v in data["bundled_tools"].values() if not v.get("available")]
    return 1 if required else 0

def platform_node_major() -> str | None:
    rc, out = run(["node", "-p", "process.versions.node.split('.')[0]"])
    return out.strip() if rc == 0 else None

if __name__ == "__main__":
    raise SystemExit(main())
