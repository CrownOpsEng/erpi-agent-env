#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
for file in "$ROOT/build.sh" "$ROOT/tests/"*.sh "$ROOT/templates/scripts/"*.sh "$ROOT/templates/bin/agent-env" "$ROOT/scripts/normalize-python-links.sh"; do
  bash -n "$file"
done
for file in "$ROOT/templates/bin/python-wrapper" "$ROOT/templates/bin/node-wrapper" "$ROOT/templates/bin/npm-wrapper" "$ROOT/templates/bin/npx-wrapper" "$ROOT/scripts/uv-isolated-exec.sh"; do
  sh -n "$file"
done
python3 -m py_compile "$ROOT/templates/scripts/doctor.py"
python3 -m py_compile "$ROOT/scripts/normalize-python-sysconfig.py"
python3 - <<'PY' "$ROOT/versions.env" "$ROOT/requirements.in" "$ROOT/requirements.lock"
import hashlib, pathlib, re, sys
versions = pathlib.Path(sys.argv[1]).read_text(encoding='utf-8')
requirements_in = pathlib.Path(sys.argv[2]).read_text(encoding='utf-8')
lock_path = pathlib.Path(sys.argv[3])
lock = lock_path.read_text(encoding='utf-8')
for name, value in re.findall(r'^(\w+_SHA256)="([0-9a-f]+)"$', versions, flags=re.M):
    assert len(value) == 64, (name, value)
expected_lock = re.search(r'^PYTHON_LOCK_SHA256="([0-9a-f]{64})"$', versions, flags=re.M).group(1)
actual_lock = hashlib.sha256(lock_path.read_bytes()).hexdigest()
assert actual_lock == expected_lock, (actual_lock, expected_lock)
assert '/tmp/' not in lock and '# via' not in lock and 'Build Root' not in lock
packages = re.findall(r'^([A-Za-z0-9_.-]+)==([^ \\\n]+)', lock, flags=re.M)
assert len(packages) == 21, len(packages)
locked = {name.lower(): version for name, version in packages}
for line in requirements_in.splitlines():
    line = line.strip()
    if not line or line.startswith('#'):
        continue
    name, version = line.split('==', 1)
    assert locked.get(name.lower()) == version, (name, version, locked.get(name.lower()))
print('hash-and-lock-shapes-ok')
PY
rm -rf "$ROOT/templates/scripts/__pycache__" "$ROOT/scripts/__pycache__"
for file in requirements.lock templates/AGENTS.md templates/RUNTIME-README.md templates/scripts/github.sh templates/scripts/doctor.py templates/bin/agent-env scripts/uv-isolated-exec.sh; do
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
grep -F 'import httpx, jsonschema, packaging, yaml, tomlkit, pytest, rpds' "$ROOT/templates/scripts/selftest.sh" >/dev/null
grep -F 'from yaml import CLoader' "$ROOT/templates/scripts/selftest.sh" >/dev/null
grep -Fx 'pytest --version >/dev/null' "$ROOT/templates/scripts/selftest.sh" >/dev/null
grep -Fx 'pip --version >/dev/null' "$ROOT/templates/scripts/selftest.sh" >/dev/null
# pyvenv.cfg is the sole relocation-mutable venv file: preserve uv metadata and patch only `home`.
grep -F -- "--exclude='pyvenv.cfg' \"\$ORIGINAL_BUILD_ROOT\"" "$ROOT/build.sh" >/dev/null
! grep -F 'executable = $PYROOT_LINK' "$ROOT/templates/scripts/repair-python.sh"
grep -F 'Fresh extraction retained its archive-build location' "$ROOT/build.sh" >/dev/null
"$ROOT/tests/github-auth-check.sh"
"$ROOT/tests/uv-isolation-check.sh"
"$ROOT/tests/repair-python-check.sh"
"$ROOT/tests/python-link-relocation-check.sh"
"$ROOT/tests/sysconfig-relocation-check.sh"
node_fetch_count="$(grep -Fc 'fetch "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" "$NODE_AR"' "$ROOT/build.sh")"
[[ "$node_fetch_count" == 1 ]] || { echo "Expected exactly one Node fetch call, found $node_fetch_count" >&2; exit 1; }
echo "Builder static checks passed."
