#!/usr/bin/env python3
from __future__ import annotations
import argparse, json, pathlib
ROOT = pathlib.Path(__file__).resolve().parents[1]

def main() -> int:
    ap=argparse.ArgumentParser(); ap.add_argument('--json',action='store_true'); ns=ap.parse_args()
    data=json.loads((ROOT/'manifest/environment.json').read_text(encoding='utf-8'))
    caps=data.get('capabilities', {})
    if ns.json:
        print(json.dumps(caps, indent=2, sort_keys=True)); return 0
    for group, value in caps.items():
        if isinstance(value, dict):
            print(f"{group}:")
            for k,v in value.items(): print(f"  {k}: {v}")
        else: print(f"{group}: {value}")
    return 0
if __name__=='__main__': raise SystemExit(main())
