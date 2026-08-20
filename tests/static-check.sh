#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
for file in "$ROOT/build.sh" "$ROOT/tests/"*.sh "$ROOT/templates/scripts/"*.sh "$ROOT/templates/bin/agent-env" "$ROOT/scripts/normalize-python-links.sh"; do
  bash -n "$file"
done
for file in "$ROOT/templates/bin/python-wrapper" "$ROOT/templates/bin/node-wrapper" "$ROOT/templates/bin/npm-wrapper" "$ROOT/templates/bin/npx-wrapper" "$ROOT/scripts/uv-isolated-exec.sh"; do
  sh -n "$file"
done
for file in "$ROOT/templates/scripts/"*.py; do python3 -m py_compile "$file"; done
python3 -m py_compile "$ROOT/scripts/normalize-python-sysconfig.py"
python3 -m py_compile "$ROOT/scripts/write-acceptance-metadata.py"
python3 - <<'PY' "$ROOT/versions.env" "$ROOT/requirements.in" "$ROOT/requirements.lock" "$ROOT"
import hashlib, pathlib, re, sys
versions_path, req_in_path, lock_path, root = map(pathlib.Path, sys.argv[1:])
versions=versions_path.read_text(encoding='utf-8'); req_in=req_in_path.read_text(encoding='utf-8'); lock=lock_path.read_text(encoding='utf-8')
vals=dict(re.findall(r'^(\w+)="([^"]*)"$', versions, flags=re.M))
for name,value in vals.items():
    if name.endswith('_SHA256'): assert re.fullmatch(r'[0-9a-f]{64}',value),(name,value)
assert hashlib.sha256(lock_path.read_bytes()).hexdigest()==vals['PYTHON_LOCK_SHA256']
assert '/tmp/' not in lock and '# via' not in lock and 'Build Root' not in lock
packages=re.findall(r'^([A-Za-z0-9_.-]+)==([^ \\n]+)',lock,flags=re.M); locked={n.lower():v for n,v in packages}
for line in req_in.splitlines():
    line=line.strip()
    if not line or line.startswith('#'): continue
    name,version=line.split('==',1); name=re.sub(r'\[.*\]$','',name)
    assert locked.get(name.lower())==version,(name,version,locked.get(name.lower()))
assert 'pytest' not in locked and 'setuptools' not in locked and 'wheel' not in locked
checks={
 'vendor/database/postgres-server-17.10-linux-x64.txz':'POSTGRES_SERVER_SHA256',
 'vendor/database/postgresql-client-17.10-linux-x64-gnu.tar.gz':'POSTGRES_CLIENT_SHA256',
 'vendor/database/plpgsql-check-2.8.11-pg17-linux-x64-gnu.tar.gz':'PLPGSQL_CHECK_SHA256',
 'vendor/node-capsules/postgres-3.4.7.tgz':'POSTGRES_JS_SHA256',
 'vendor/node-capsules/postgres-language-server-wasm-0.25.7.tgz':'PGLS_WASM_SHA256',
 'vendor/node-capsules/fast-check-4.9.0.tgz':'FAST_CHECK_SHA256',
 'vendor/node-capsules/pure-rand-8.4.2.tgz':'PURE_RAND_SHA256'}
for rel,key in checks.items():
    path=root/rel; assert path.is_file(),rel
    assert hashlib.sha256(path.read_bytes()).hexdigest()==vals[key],(rel,key)
print('hash-lock-and-vendor-shapes-ok')
PY
rm -rf "$ROOT/templates/scripts/__pycache__" "$ROOT/scripts/__pycache__"
for file in requirements.lock templates/AGENTS.md templates/RUNTIME-README.md templates/scripts/github.sh templates/scripts/doctor.py templates/scripts/postgres.py templates/scripts/pgtap.py templates/scripts/node-deps.py templates/scripts/capabilities.py templates/bin/agent-env scripts/uv-isolated-exec.sh scripts/write-acceptance-metadata.py scripts/rebuild-qualified-database-assets.sh; do
  [[ -s "$ROOT/$file" ]] || { echo "Required runtime/build source missing: $file" >&2; exit 1; }
done
# The router is intentionally compact; large operational detail belongs in README/commands.
router_bytes="$(wc -c < "$ROOT/templates/AGENTS.md")"
(( router_bytes <= 3000 )) || { echo "templates/AGENTS.md is too large for a routing surface: ${router_bytes} bytes" >&2; exit 1; }
# Authentication must remain host/session state, not redirected into the portable payload.
if grep -R -nE 'export[[:space:]]+GH_CONFIG_DIR=|GH_CONFIG_DIR=' "$ROOT/templates"; then
  echo "Do not redirect GitHub credential storage into the portable bundle." >&2
  exit 1
fi
# Ad-hoc package/runtime installation belongs in mutable state rather than verified payload directories.
grep -F 'UV_PYTHON_INSTALL_DIR="$MAGNET_AGENT_ENV/state/uv-python"' "$ROOT/templates/activate" >/dev/null
grep -F 'NPM_CONFIG_PREFIX="$MAGNET_AGENT_ENV/state/npm-global"' "$ROOT/templates/activate" >/dev/null
# Mutable state is outside immutable payload verification/topology and is pristine in the distributed archive.
grep -F "! -path './state/*'" "$ROOT/templates/scripts/verify.sh" >/dev/null
grep -F '! -path "$ROOT/state/*"' "$ROOT/templates/scripts/selftest.sh" >/dev/null
grep -F 'log "Reset mutable state for distribution"' "$ROOT/build.sh" >/dev/null
grep -F 'reset_runtime_state' "$ROOT/build.sh" >/dev/null
grep -F 'Mutable state was not pristine before packaging:' "$ROOT/build.sh" >/dev/null
# No shipped shell path may use an early-closing `head` pipeline under `set -o pipefail`.
if grep -R -nE '\|[[:space:]]*head([[:space:]]|$)' "$ROOT/build.sh" "$ROOT/templates" "$ROOT/tests" "$ROOT/scripts"; then
  echo "Avoid early-closing head pipelines under pipefail; capture output or consume it fully." >&2
  exit 1
fi
grep -F 'getconf GNU_LIBC_VERSION' "$ROOT/build.sh" >/dev/null
grep -F 'MIN_KERNEL_VERSION="4.18"' "$ROOT/versions.env" >/dev/null
grep -F 'MIN_GLIBC_VERSION="2.28"' "$ROOT/versions.env" >/dev/null
grep -F 'MIN_GLIBCXX_SYMBOL="GLIBCXX_3.4.25"' "$ROOT/versions.env" >/dev/null
# yq is verified directly against the immutable GitHub release-asset digest; do not parse rhash columns.
grep -F 'YQ_SHA256="fa52a4e758c63d38299163fbdd1edfb4c4963247918bf9c1c5d31d84789eded4"' "$ROOT/versions.env" >/dev/null
! grep -R -nE 'YQ_CHECKSUMS_SHA256|YQ_HASH|yq-checksums|awk.*yq_linux_amd64' "$ROOT/build.sh" "$ROOT/versions.env"
grep -F "find . -xtype l ! -path './state/*'" "$ROOT/templates/scripts/verify.sh" >/dev/null
# The v1 Python lock is source-controlled input, not resolved during hydration.
grep -F 'verify_one "$SELF_DIR/requirements.lock" "$PYTHON_LOCK_SHA256"' "$ROOT/build.sh" >/dev/null
! grep -F 'pip compile' "$ROOT/build.sh"
# Pip bootstrap code is verified before execution.
grep -F 'verify_one "$PIP_BOOT_WHEEL" "$PIP_BOOTSTRAP_WHEEL_SHA256"' "$ROOT/build.sh" >/dev/null
grep -F 'PIP_BOOT_CACHE="$DL/pip-26.1.2-py3-none-any.whl"' "$ROOT/build.sh" >/dev/null
# uv build/recovery operations are isolated from project/user selection overrides without suppressing proxy/CA settings.
grep -F 'UV_NO_CONFIG=1' "$ROOT/scripts/uv-isolated-exec.sh" >/dev/null
grep -F 'unset UV_PYTHON_DOWNLOADS_JSON_URL' "$ROOT/scripts/uv-isolated-exec.sh" >/dev/null
# Build-time caches live beside direct-download cache, not in the disposable payload tree.
grep -F 'BUILDER_UV_PYTHON_CACHE="$CACHE_DIR/uv-python-archives"' "$ROOT/build.sh" >/dev/null
grep -F 'UV_PYTHON_CACHE_DIR="$BUILDER_UV_PYTHON_CACHE"' "$ROOT/build.sh" >/dev/null
grep -F 'PIP_CACHE_DIR="$BUILDER_PIP_CACHE"' "$ROOT/build.sh" >/dev/null
# uv-managed absolute convenience links are preserved semantically but made relative.
grep -F 'normalize-python-links.sh" "$BUILD/runtime/python"' "$ROOT/build.sh" >/dev/null
# uv-managed Python sysconfig is normalized into a location-neutral, immutable file.
grep -F '__MAGNET_AGENT_PYTHON_PREFIX__' "$ROOT/scripts/normalize-python-sysconfig.py" >/dev/null
grep -F "sysconfig.get_config_var('BINDIR')" "$ROOT/templates/scripts/selftest.sh" >/dev/null
# Native/compiled Python and uv-generated console entrypoints are exercised after each relocation/rebuild.
grep -F 'import httpx, jsonschema, packaging, yaml, tomlkit, rpds' "$ROOT/templates/scripts/selftest.sh" >/dev/null
grep -F 'from yaml import CLoader' "$ROOT/templates/scripts/selftest.sh" >/dev/null
! grep -F 'pytest --version' "$ROOT/templates/scripts/selftest.sh"
grep -Fx 'pip --version >/dev/null' "$ROOT/templates/scripts/selftest.sh" >/dev/null
# Offline rebuilds must canonicalize uv's timestamp-bearing installer metadata before integrity verification.
grep -F "cache=dist/'uv_cache.json'" "$ROOT/templates/scripts/selftest.sh" >/dev/null
grep -F "cache_record=f'{dist.name}/uv_cache.json'" "$ROOT/templates/scripts/selftest.sh" >/dev/null
grep -F "csv.writer(h,lineterminator='\\n').writerows(kept)" "$ROOT/templates/scripts/selftest.sh" >/dev/null
selftest_line="$(grep -nF '"$ROOT/scripts/selftest.sh"' "$ROOT/templates/scripts/rebuild-python.sh" | cut -d: -f1)"
verify_line="$(grep -nF '"$ROOT/scripts/verify.sh"' "$ROOT/templates/scripts/rebuild-python.sh" | cut -d: -f1)"
[[ -n "$selftest_line" && -n "$verify_line" && "$selftest_line" -lt "$verify_line" ]] || {
  echo "Offline rebuild must canonicalize through selftest before immutable verification." >&2
  exit 1
}
# pyvenv.cfg is the sole relocation-mutable venv file: preserve uv metadata and patch only `home`.
grep -F -- "--exclude='pyvenv.cfg' \"\$ORIGINAL_BUILD_ROOT\"" "$ROOT/build.sh" >/dev/null
! grep -F 'executable = $PYROOT_LINK' "$ROOT/templates/scripts/repair-python.sh"
grep -F 'Fresh extraction retained its archive-build location' "$ROOT/build.sh" >/dev/null
# GitHub OAuth must not persist a relocatable gh path into host-global Git config.
grep -F 'GH_PROMPT_DISABLED=1 gh auth login --hostname "$HOST" --git-protocol https --web' "$ROOT/templates/scripts/github.sh" >/dev/null
grep -F "git config --local --add credential.https://github.com.helper '!gh auth git-credential'" "$ROOT/templates/scripts/github.sh" >/dev/null
grep -F 'git push --dry-run --no-verify' "$ROOT/templates/scripts/github.sh" >/dev/null
grep -F 'github-git' "$ROOT/templates/bin/agent-env" >/dev/null
grep -F 'github-git' "$ROOT/templates/AGENTS.md" >/dev/null
if grep -R -nF 'gh auth setup-git' "$ROOT/templates/scripts" "$ROOT/templates/bin"; then
  echo "Do not persist the portable gh path with gh auth setup-git." >&2
  exit 1
fi
if grep -R -nE 'git[[:space:]]+config[[:space:]]+--global.*credential' "$ROOT/templates/scripts" "$ROOT/templates/bin"; then
  echo "Do not write Git credential helpers globally from the portable bundle." >&2
  exit 1
fi
grep -F 'BUNDLE_VERSION="0.2.0"' "$ROOT/versions.env" >/dev/null
grep -F 'POSTGRES_VERSION="17.10"' "$ROOT/versions.env" >/dev/null
grep -F 'agent-env postgres run' "$ROOT/templates/RUNTIME-README.md" >/dev/null
grep -F 'agent-env node-deps hydrate' "$ROOT/templates/RUNTIME-README.md" >/dev/null
grep -F 'Do not fragment a suite merely to satisfy an agent wrapper timeout.' "$ROOT/templates/AGENTS.md" >/dev/null
grep -F 'Unsupported bundled PostgreSQL client tool' "$ROOT/templates/bin/agent-env" >/dev/null
grep -F 'DATABASE_URL' "$ROOT/templates/scripts/postgres.py" >/dev/null
grep -F '127.0.0.1' "$ROOT/templates/scripts/postgres.py" >/dev/null
grep -F 'pg_checksums' "$ROOT/templates/scripts/postgres.py" >/dev/null
grep -F "unix_socket_directories = ''" "$ROOT/templates/scripts/postgres.py" >/dev/null
grep -F -- '--- PostgreSQL startup log ---' "$ROOT/templates/scripts/postgres.py" >/dev/null
! grep -F 'cluster / "socket"' "$ROOT/templates/scripts/postgres.py" >/dev/null
grep -F 'package-lock.json is required' "$ROOT/templates/scripts/node-deps.py" >/dev/null
! grep -R -nE 'anon|authenticated|service_role|magnet\.' "$ROOT/templates/scripts/postgres.py" "$ROOT/templates/scripts/pgtap.py" "$ROOT/templates/scripts/node-deps.py"
"$ROOT/tests/github-auth-check.sh"
"$ROOT/tests/acceptance-metadata-check.sh"
"$ROOT/tests/uv-isolation-check.sh"
"$ROOT/tests/repair-python-check.sh"
"$ROOT/tests/python-link-relocation-check.sh"
"$ROOT/tests/sysconfig-relocation-check.sh"
node_fetch_count="$(grep -Fc 'fetch "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" "$NODE_AR"' "$ROOT/build.sh")"
[[ "$node_fetch_count" == 1 ]] || { echo "Expected exactly one Node fetch call, found $node_fetch_count" >&2; exit 1; }
echo "Builder static checks passed."
