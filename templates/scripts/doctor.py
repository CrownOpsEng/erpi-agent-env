#!/usr/bin/env python3
from __future__ import annotations
import argparse, json, os, pathlib, platform, shutil, subprocess, sys
from typing import Any
ROOT = pathlib.Path(__file__).resolve().parents[1]

def run(args: list[str], timeout: int = 6) -> tuple[int,str]:
    try:
        p=subprocess.run(args,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=timeout,check=False)
        return p.returncode,p.stdout.strip()
    except (OSError, subprocess.TimeoutExpired) as e:
        return 127,str(e)

def probe(path: pathlib.Path, args: list[str]) -> dict[str,Any]:
    if not path.exists(): return {'available':False}
    rc,out=run([str(path),*args])
    return {'available':rc==0,'path':str(path),'returncode':rc,'output':out.splitlines()[0] if out else ''}

def host(command: str, args: list[str]|None=None) -> dict[str,Any]:
    p=shutil.which(command)
    if not p:return {'available':False}
    rc,out=run([p,*(args or ['--version'])])
    return {'available':rc==0,'path':p,'returncode':rc,'output':out.splitlines()[0] if out else ''}

def main()->int:
    ap=argparse.ArgumentParser(); ap.add_argument('--json',action='store_true'); ns=ap.parse_args()
    manifest=json.loads((ROOT/'manifest/environment.json').read_text(encoding='utf-8'))
    data={
      'bundle':{'root':str(ROOT),'version':manifest.get('product_version'),'target':manifest.get('target')},
      'bundled':{
        'python':probe(ROOT/'env/bin/python',['--version']),
        'node':probe(ROOT/'bin/node',['--version']),
        'node_yaml':probe(ROOT/'bin/node',['-e',"const Y=require('yaml'); if(require('yaml/package.json').version!=='2.9.0'||Y.parse('a: 1').a!==1) process.exit(1); console.log('yaml 2.9.0')"]),
        'gh':probe(ROOT/'bin/gh',['--version']),
        'shellcheck':probe(ROOT/'bin/shellcheck',['--version']),
        'mlr':probe(ROOT/'bin/mlr',['--version']),
        'httpx_cli':probe(ROOT/'env/bin/httpx',['--help']),
        'supabase':probe(ROOT/'bin/supabase',['--version']),
        'postgres_server':probe(ROOT/'runtime/postgres/server/bin/postgres',['--version']),
        'psql':probe(ROOT/'runtime/postgres/client/bin/psql',['--version']),
      },
      'host':{k:host(k) for k in ('git','make','docker','podman','curl')},
      'repository':{
        'cwd':str(pathlib.Path.cwd()),
        'git':(pathlib.Path.cwd()/'.git').exists(),
        'agents':(pathlib.Path.cwd()/'AGENTS.md').is_file(),
        'makefile':(pathlib.Path.cwd()/'Makefile').is_file(),
        'package_lock':(pathlib.Path.cwd()/'package-lock.json').is_file(),
      },
      'runtime':{'system':platform.system(),'machine':platform.machine()},
      'capabilities':manifest.get('capabilities',{}),
    }
    if ns.json: print(json.dumps(data,indent=2,sort_keys=True))
    else:
        print(f"ERPI Agent Environment {data['bundle']['version']} @ {ROOT}")
        for name,p in data['bundled'].items(): print(f"bundled {name}: {'yes' if p.get('available') else 'NO'} {p.get('output','')}")
        for name,p in data['host'].items(): print(f"host {name}: {'yes' if p.get('available') else 'no'}")
        print('repo:', ', '.join(k for k,v in data['repository'].items() if isinstance(v,bool) and v) or 'no repository markers')
    missing=[k for k,v in data['bundled'].items() if not v.get('available')]
    return 1 if missing else 0
if __name__=='__main__': raise SystemExit(main())
