#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/agent-env-node-deps-check.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
RUNTIME="$TMP/runtime"
mkdir -p "$RUNTIME/scripts" "$RUNTIME/runtime/node-capsules" "$RUNTIME/manifest"
cp "$ROOT/templates/scripts/node-deps.py" "$RUNTIME/scripts/node-deps.py"
cp "$ROOT/vendor/node-capsules/manifest.json" "$RUNTIME/manifest/node-capsules.json"
chmod +x "$RUNTIME/scripts/node-deps.py"

# Source validation stays network-free: generate deterministic local package fixtures,
# then bind the runtime-copy manifest to those exact bytes. The real connected builder
# separately proves acquisition of the upstream capsules from the same source manifest.
python3 - <<'PY' "$RUNTIME/manifest/node-capsules.json" "$RUNTIME/runtime/node-capsules" "$TMP/package-lock.template.json"
import base64, gzip, hashlib, io, json, pathlib, tarfile, sys
manifest_path=pathlib.Path(sys.argv[1]); capsule_dir=pathlib.Path(sys.argv[2]); lock_path=pathlib.Path(sys.argv[3])
manifest=json.loads(manifest_path.read_text(encoding='utf-8'))
packages={"": {"name":"fixture","version":"1.0.0"}}
for name,cap in manifest["packages"].items():
    package_json=json.dumps({"name":name,"version":cap["version"],"type":"module"},sort_keys=True,separators=(',',':')).encode()+b'\n'
    files={"package/package.json":package_json,"package/src/index.js":b'export default true\n'}
    raw=io.BytesIO()
    with tarfile.open(fileobj=raw,mode='w',format=tarfile.GNU_FORMAT) as tf:
        for rel,data in sorted(files.items()):
            info=tarfile.TarInfo(rel); info.size=len(data); info.mtime=0; info.mode=0o644; info.uid=0; info.gid=0; info.uname=''; info.gname=''
            tf.addfile(info,io.BytesIO(data))
    out=capsule_dir/cap['file']
    with out.open('wb') as handle:
        with gzip.GzipFile(filename='',mode='wb',fileobj=handle,mtime=0) as gz: gz.write(raw.getvalue())
    data=out.read_bytes()
    cap['sha256']=hashlib.sha256(data).hexdigest()
    cap['integrity']='sha512-'+base64.b64encode(hashlib.sha512(data).digest()).decode()
    packages[f"node_modules/{name}"]={"version":cap["version"],"integrity":cap["integrity"]}
manifest_path.write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
lock_path.write_text(json.dumps({"name":"fixture","version":"1.0.0","lockfileVersion":3,"requires":True,"packages":packages},indent=2)+'\n',encoding='utf-8')
PY

make_repo() {
  local repo="$1"
  mkdir -p "$repo"
  cp "$TMP/package-lock.template.json" "$repo/package-lock.json"
  printf '{"name":"fixture","version":"1.0.0","type":"module"}\n' > "$repo/package.json"
}
run_deps() { python3 "$RUNTIME/scripts/node-deps.py" --repo "$1" "$2"; }

# Happy path records content-bound ownership and removes only owned packages.
repo="$TMP/happy"; make_repo "$repo"
run_deps "$repo" hydrate >/dev/null
python3 - <<'PY' "$repo/node_modules/.agent-env-node-deps.json"
import json,re,sys
marker=json.load(open(sys.argv[1],encoding='utf-8'))
assert marker['schema']==2 and len(marker['packages'])==6
for record in marker['packages'].values():
    assert re.fullmatch(r'[0-9a-f]{64}',record['tree_sha256'])
PY
run_deps "$repo" clean >/dev/null
[[ ! -e "$repo/node_modules/.agent-env-node-deps.json" ]]

# A lock mismatch refuses before node_modules exists.
repo="$TMP/mismatch"; make_repo "$repo"
python3 - <<'PY' "$repo/package-lock.json"
import json,sys
p=sys.argv[1]; data=json.load(open(p,encoding='utf-8'))
data['packages']['node_modules/postgres']['version']='9.9.9'
json.dump(data,open(p,'w',encoding='utf-8'),indent=2)
PY
if run_deps "$repo" hydrate >/dev/null 2>&1; then echo 'lock mismatch unexpectedly hydrated' >&2; exit 1; fi
[[ ! -e "$repo/node_modules" ]]

# A late package conflict must be preflighted: no earlier package may be written.
repo="$TMP/foreign"; make_repo "$repo"
mkdir -p "$repo/node_modules/@postgres-language-server/wasm"
printf '{}\n' > "$repo/node_modules/@postgres-language-server/wasm/not-package-json"
if run_deps "$repo" hydrate >/dev/null 2>&1; then echo 'foreign path unexpectedly hydrated' >&2; exit 1; fi
[[ ! -e "$repo/node_modules/postgres" ]]
[[ -f "$repo/node_modules/@postgres-language-server/wasm/not-package-json" ]]

# Symlinked node_modules or scoped parents must never redirect writes outside the repository.
repo="$TMP/scope-symlink"; outside="$TMP/outside-scope"; make_repo "$repo"; mkdir -p "$repo/node_modules" "$outside"
ln -s "$outside" "$repo/node_modules/@postgres-language-server"
if run_deps "$repo" hydrate >/dev/null 2>&1; then echo 'scoped symlink unexpectedly hydrated' >&2; exit 1; fi
[[ ! -e "$outside/wasm" && ! -e "$repo/node_modules/postgres" ]]

repo="$TMP/node-modules-symlink"; outside="$TMP/outside-node-modules"; make_repo "$repo"; mkdir -p "$outside"
ln -s "$outside" "$repo/node_modules"
if run_deps "$repo" hydrate >/dev/null 2>&1; then echo 'node_modules symlink unexpectedly hydrated' >&2; exit 1; fi
[[ -z "$(find "$outside" -mindepth 1 -print -quit)" ]]

# Cleanup refuses changed content before deleting any recorded package.
repo="$TMP/modified-clean"; make_repo "$repo"; run_deps "$repo" hydrate >/dev/null
printf '\n// changed\n' >> "$repo/node_modules/postgres/src/index.js"
if run_deps "$repo" clean >/dev/null 2>&1; then echo 'modified owned package unexpectedly cleaned' >&2; exit 1; fi
[[ -d "$repo/node_modules/postgres" && -d "$repo/node_modules/fast-check" && -f "$repo/node_modules/.agent-env-node-deps.json" ]]

# A matching package already supplied by the repository stays foreign and survives cleanup.
repo="$TMP/foreign-match"; make_repo "$repo"; mkdir -p "$repo/node_modules/postgres"
tar -xOzf "$RUNTIME/runtime/node-capsules/postgres-3.4.7.tgz" package/package.json > "$repo/node_modules/postgres/package.json"
printf 'foreign sentinel\n' > "$repo/node_modules/postgres/KEEP"
run_deps "$repo" hydrate >/dev/null
python3 - <<'PY' "$repo/node_modules/.agent-env-node-deps.json"
import json,sys
marker=json.load(open(sys.argv[1],encoding='utf-8'))
assert 'postgres' not in marker['packages'] and len(marker['packages'])==5
PY
run_deps "$repo" clean >/dev/null
[[ -f "$repo/node_modules/postgres/KEEP" ]]

# RC1's name-only marker is not trustworthy enough to delete repository files.
repo="$TMP/legacy"; make_repo "$repo"; mkdir -p "$repo/node_modules/postgres"
tar -xOzf "$RUNTIME/runtime/node-capsules/postgres-3.4.7.tgz" package/package.json > "$repo/node_modules/postgres/package.json"
printf '{"packages":["postgres"]}\n' > "$repo/node_modules/.agent-env-node-deps.json"
if run_deps "$repo" clean >/dev/null 2>&1; then echo 'legacy ownership marker unexpectedly trusted' >&2; exit 1; fi
[[ -d "$repo/node_modules/postgres" ]]

echo 'Node capsule safety checks passed.'
