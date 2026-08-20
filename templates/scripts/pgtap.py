#!/usr/bin/env python3
from __future__ import annotations
import argparse, os, pathlib, re, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
PSQL = ROOT / "runtime/postgres/client/bin/psql"
LIB = ROOT / "runtime/postgres/client/lib"


def main() -> int:
    ap = argparse.ArgumentParser(description="Run pgTAP SQL files with strict TAP accounting.")
    ap.add_argument("files", nargs="+")
    ns = ap.parse_args()
    total = 0
    env = dict(os.environ)
    env["LD_LIBRARY_PATH"] = str(LIB) + ((":" + env["LD_LIBRARY_PATH"]) if env.get("LD_LIBRARY_PATH") else "")
    for item in ns.files:
        path = pathlib.Path(item)
        proc = subprocess.run([str(PSQL), "-X", "-v", "ON_ERROR_STOP=1", "-At", "-f", str(path)], env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        out = proc.stdout
        if proc.returncode != 0:
            sys.stderr.write(out)
            return proc.returncode
        if re.search(r"(?mi)^Bail out!", out) or re.search(r"(?mi)^not ok\b", out):
            sys.stderr.write(out)
            return 1
        plans = [int(m.group(1)) for m in re.finditer(r"(?m)^1\.\.(\d+)\s*$", out)]
        oks = len(re.findall(r"(?m)^ok\b", out))
        if len(plans) != 1 or oks != plans[0]:
            sys.stderr.write(out)
            print(f"pgTAP accounting mismatch for {path}: plans={plans} ok={oks}", file=sys.stderr)
            return 1
        total += oks
        print(f"PASS {path}: {oks}/{plans[0]}")
    print(f"pgTAP PASS: {len(ns.files)} file(s), {total} assertion(s)")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
