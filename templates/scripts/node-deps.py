#!/usr/bin/env python3
from __future__ import annotations
import argparse, base64, hashlib, json, os, pathlib, shutil, tarfile, tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
CAPSULE_DIR = ROOT / 'runtime/node-capsules'
MANIFEST = ROOT / 'manifest/node-capsules.json'
MARKER = '.agent-env-node-deps.json'


def sri_ok(path: pathlib.Path, sri: str) -> bool:
    algo, expected = sri.split('-', 1)
    h = hashlib.new(algo)
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return base64.b64encode(h.digest()).decode() == expected


def safe_members(tf: tarfile.TarFile):
    for m in tf.getmembers():
        p = pathlib.PurePosixPath(m.name)
        if p.is_absolute() or '..' in p.parts:
            raise RuntimeError(f'unsafe archive member: {m.name}')
        if m.islnk() or m.issym() or m.isdev():
            raise RuntimeError(f'unsupported archive member type: {m.name}')
        yield m


def lock_entry(lock: dict, name: str) -> dict | None:
    packages = lock.get('packages') or {}
    key = f"node_modules/{name}"
    return packages.get(key)


def package_dest(repo: pathlib.Path, name: str) -> pathlib.Path:
    return repo / 'node_modules' / pathlib.Path(*name.split('/'))


def load_manifest() -> dict:
    return json.loads(MANIFEST.read_text(encoding='utf-8'))


def load_lock(repo: pathlib.Path) -> dict:
    path = repo / 'package-lock.json'
    if not path.is_file():
        raise SystemExit('package-lock.json is required; repository lock remains authority.')
    return json.loads(path.read_text(encoding='utf-8'))


def inspect(repo: pathlib.Path) -> tuple[list[tuple[str, dict, pathlib.Path]], list[str]]:
    manifest = load_manifest(); lock = load_lock(repo); ready=[]; problems=[]
    for name, cap in manifest['packages'].items():
        entry = lock_entry(lock, name)
        if not entry:
            continue
        if entry.get('version') != cap['version'] or entry.get('integrity') != cap['integrity']:
            problems.append(f"{name}: lock mismatch (expected {cap['version']} and pinned integrity)")
            continue
        archive = CAPSULE_DIR / cap['file']
        actual = hashlib.sha256(archive.read_bytes()).hexdigest()
        if actual != cap['sha256'] or not sri_ok(archive, cap['integrity']):
            problems.append(f"{name}: capsule integrity failure")
            continue
        ready.append((name, cap, archive))
    return ready, problems


def cmd_status(repo: pathlib.Path) -> int:
    ready, problems = inspect(repo)
    for name, cap, _ in ready:
        dest=package_dest(repo,name)
        state='present' if (dest/'package.json').is_file() else 'available'
        print(f"{name}@{cap['version']}: {state}")
    for p in problems: print(f"ERROR {p}")
    return 1 if problems else 0


def cmd_hydrate(repo: pathlib.Path) -> int:
    ready, problems = inspect(repo)
    if problems:
        for p in problems: print(f"ERROR {p}")
        return 1
    nm=repo/'node_modules'; nm.mkdir(exist_ok=True)
    marker_path=nm/MARKER
    owned=[]
    if marker_path.is_file():
        try: owned=json.loads(marker_path.read_text()).get('packages', [])
        except Exception: raise SystemExit(f'invalid ownership marker: {marker_path}')
    for name, cap, archive in ready:
        dest=package_dest(repo,name)
        if dest.exists():
            pkg=dest/'package.json'
            if not pkg.is_file(): raise SystemExit(f'refusing to overwrite foreign path: {dest}')
            meta=json.loads(pkg.read_text(encoding='utf-8'))
            if meta.get('name') != name or meta.get('version') != cap['version']:
                raise SystemExit(f'refusing to overwrite mismatching package: {dest}')
            print(f"{name}@{cap['version']}: already present")
            continue
        dest.parent.mkdir(parents=True, exist_ok=True)
        tmp=dest.parent/(dest.name+'.agent-env.tmp')
        shutil.rmtree(tmp, ignore_errors=True); tmp.mkdir()
        with tarfile.open(archive, 'r:gz') as tf:
            members=list(safe_members(tf))
            tf.extractall(tmp, members=members, filter='data')
        package_dir=tmp/'package'
        meta=json.loads((package_dir/'package.json').read_text(encoding='utf-8'))
        if meta.get('name') != name or meta.get('version') != cap['version']:
            shutil.rmtree(tmp, ignore_errors=True); raise SystemExit(f'capsule metadata mismatch for {name}')
        package_dir.rename(dest); shutil.rmtree(tmp, ignore_errors=True)
        if name not in owned: owned.append(name)
        print(f"{name}@{cap['version']}: hydrated")
    marker_path.write_text(json.dumps({'packages': sorted(owned)}, indent=2)+'\n', encoding='utf-8')
    return 0


def cmd_clean(repo: pathlib.Path) -> int:
    marker=repo/'node_modules'/MARKER
    if not marker.is_file():
        print('No agent-env hydrated packages recorded.'); return 0
    data=json.loads(marker.read_text(encoding='utf-8'))
    for name in data.get('packages', []):
        dest=package_dest(repo,name)
        if dest.exists(): shutil.rmtree(dest); print(f"removed {name}")
    marker.unlink(missing_ok=True)
    return 0


def main() -> int:
    ap=argparse.ArgumentParser(description='Hydrate exact repository-locked Node packages from immutable offline capsules without editing manifests.')
    ap.add_argument('--repo', default='.')
    sub=ap.add_subparsers(dest='cmd',required=True)
    for x in ('status','hydrate','clean'): sub.add_parser(x)
    ns=ap.parse_args(); repo=pathlib.Path(ns.repo).resolve()
    return {'status':cmd_status,'hydrate':cmd_hydrate,'clean':cmd_clean}[ns.cmd](repo)
if __name__=='__main__': raise SystemExit(main())
