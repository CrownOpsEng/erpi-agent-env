#!/usr/bin/env bash
set -euo pipefail
umask 022

SELF_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck disable=SC1091
source "$SELF_DIR/versions.env"

OUT_DIR="$SELF_DIR/dist"
CACHE_DIR="$SELF_DIR/.download-cache"
KEEP_WORK=0

usage() {
  cat <<USAGE
Usage: ./build.sh [--out DIR] [--cache DIR] [--keep-work]

Build ERPI Agent Environment product ${PRODUCT_VERSION} for ${TARGET}.
Artifact identity is derived from Git release/prerelease ancestry. Exported source trees without .git must provide ERPI_AGENT_SOURCE_COMMIT, ERPI_AGENT_SOURCE_BASE_TAG, ERPI_AGENT_SOURCE_DISTANCE, and ERPI_AGENT_SOURCE_DESCRIPTION.
Requires an internet-connected supported Linux x86-64 host (kernel >= ${MIN_KERNEL_VERSION}, glibc >= ${MIN_GLIBC_VERSION}) with a working Docker daemon. No sudo is used.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) OUT_DIR="$2"; shift 2 ;;
    --cache) CACHE_DIR="$2"; shift 2 ;;
    --keep-work) KEEP_WORK=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

SOURCE_COMMIT="${ERPI_AGENT_SOURCE_COMMIT:-}"
SOURCE_BASE_TAG="${ERPI_AGENT_SOURCE_BASE_TAG:-}"
SOURCE_DISTANCE="${ERPI_AGENT_SOURCE_DISTANCE:-}"
SOURCE_DESCRIPTION="${ERPI_AGENT_SOURCE_DESCRIPTION:-}"

if command -v git >/dev/null 2>&1 && git -C "$SELF_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  CHECKOUT_COMMIT="$(git -C "$SELF_DIR" rev-parse HEAD)"
  SOURCE_STATUS="$(git -C "$SELF_DIR" status --porcelain --untracked-files=all)"
  if [[ -n "$SOURCE_STATUS" ]]; then
    echo "Distributable builds require a clean committed source tree; commit or remove these changes first:" >&2
    printf '%s\n' "$SOURCE_STATUS" >&2
    exit 1
  fi

  RESOLVED_BASE_TAG="$(git -C "$SELF_DIR" describe --tags --match 'v[0-9]*' --abbrev=0 --first-parent "$CHECKOUT_COMMIT" 2>/dev/null || true)"
  [[ -n "$RESOLVED_BASE_TAG" ]] || {
    echo "Cannot derive source ancestry: no reachable v<SemVer> release/prerelease tag." >&2
    exit 1
  }
  RESOLVED_DISTANCE="$(git -C "$SELF_DIR" rev-list --count --first-parent "${RESOLVED_BASE_TAG}..${CHECKOUT_COMMIT}")"
  if [[ "$RESOLVED_DISTANCE" == 0 ]]; then
    RESOLVED_DESCRIPTION="$RESOLVED_BASE_TAG"
  else
    RESOLVED_DESCRIPTION="${RESOLVED_BASE_TAG}-${RESOLVED_DISTANCE}-g${CHECKOUT_COMMIT:0:12}"
  fi

  for pair in \
    "SOURCE_COMMIT:$SOURCE_COMMIT:$CHECKOUT_COMMIT" \
    "SOURCE_BASE_TAG:$SOURCE_BASE_TAG:$RESOLVED_BASE_TAG" \
    "SOURCE_DISTANCE:$SOURCE_DISTANCE:$RESOLVED_DISTANCE" \
    "SOURCE_DESCRIPTION:$SOURCE_DESCRIPTION:$RESOLVED_DESCRIPTION"; do
    IFS=: read -r label supplied resolved <<<"$pair"
    if [[ -n "$supplied" && "$supplied" != "$resolved" ]]; then
      echo "ERPI_AGENT_${label} $supplied does not match checked-out source value $resolved." >&2
      exit 1
    fi
  done

  SOURCE_COMMIT="$CHECKOUT_COMMIT"
  SOURCE_BASE_TAG="$RESOLVED_BASE_TAG"
  SOURCE_DISTANCE="$RESOLVED_DISTANCE"
  SOURCE_DESCRIPTION="$RESOLVED_DESCRIPTION"

  BASE_PRODUCT_VERSION="${SOURCE_BASE_TAG#v}"
  if [[ "$PRODUCT_VERSION" != "$BASE_PRODUCT_VERSION" ]]; then
    PARENT_COMMIT="$(git -C "$SELF_DIR" rev-parse "${CHECKOUT_COMMIT}^1" 2>/dev/null || true)"
    if [[ -n "$PARENT_COMMIT" ]]; then
      PARENT_PRODUCT_VERSION="$(git -C "$SELF_DIR" show "$PARENT_COMMIT:versions.env" 2>/dev/null | sed -n 's/^PRODUCT_VERSION="\([^"]*\)"$/\1/p')"
      if [[ -n "$PARENT_PRODUCT_VERSION" && "$PARENT_PRODUCT_VERSION" == "$PRODUCT_VERSION" ]]; then
        echo "PRODUCT_VERSION $PRODUCT_VERSION is ahead of source tag $SOURCE_BASE_TAG on more than the release-cut commit; create the matching tag before further source work." >&2
        exit 1
      fi
    fi
  fi
else
  missing=()
  [[ -n "$SOURCE_COMMIT" ]] || missing+=(ERPI_AGENT_SOURCE_COMMIT)
  [[ -n "$SOURCE_BASE_TAG" ]] || missing+=(ERPI_AGENT_SOURCE_BASE_TAG)
  [[ -n "$SOURCE_DISTANCE" ]] || missing+=(ERPI_AGENT_SOURCE_DISTANCE)
  [[ -n "$SOURCE_DESCRIPTION" ]] || missing+=(ERPI_AGENT_SOURCE_DESCRIPTION)
  if ((${#missing[@]})); then
    printf 'Cannot determine source ancestry without Git. Missing exported-source identity:' >&2
    printf ' %s' "${missing[@]}" >&2
    printf '\n' >&2
    exit 1
  fi
fi

# shellcheck disable=SC1091
source "$SELF_DIR/scripts/build-identity.sh"
compute_build_identity "$PRODUCT_VERSION" "$SOURCE_COMMIT" "$SOURCE_BASE_TAG" "$SOURCE_DISTANCE" "$SOURCE_DESCRIPTION" "$TARGET"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Required build command missing: $1" >&2; exit 1; }; }
for cmd in bash curl tar gzip bzip2 xz sha256sum find file readelf grep sed awk mktemp cp mv ln chmod install readlink xargs sort du ldd uname env docker id; do need "$cmd"; done
TAR_VERSION="$(tar --version 2>/dev/null || true)"
grep -q 'GNU tar' <<<"$TAR_VERSION" || { echo "GNU tar is required by this builder." >&2; exit 1; }
[[ "$(uname -s)" == Linux ]] || { echo "Builder target is Linux only." >&2; exit 1; }
[[ "$(uname -m)" == x86_64 ]] || { echo "Builder target is x86_64 only; found $(uname -m)." >&2; exit 1; }
LIBC_INFO="$(getconf GNU_LIBC_VERSION 2>/dev/null || true)"
if [[ -z "$LIBC_INFO" ]]; then
  LIBC_INFO="$(ldd --version 2>&1 || true)"
fi
grep -Eqi 'glibc|GNU C Library|GNU libc' <<<"$LIBC_INFO" || { echo "A glibc-based build host is required. Detected: ${LIBC_INFO:-unknown}" >&2; exit 1; }
version_at_least() {
  awk -v actual="$1" -v minimum="$2" 'BEGIN {
    split(actual, a, "."); split(minimum, m, ".");
    for (i = 1; i <= 3; i++) {
      av = (a[i] == "" ? 0 : a[i] + 0); mv = (m[i] == "" ? 0 : m[i] + 0);
      if (av > mv) exit 0; if (av < mv) exit 1;
    }
    exit 0
  }'
}
GLIBC_VERSION="$(awk 'NR == 1 { for (i = NF; i >= 1; i--) if ($i ~ /^[0-9]+([.][0-9]+)+$/) { print $i; exit } }' <<<"$LIBC_INFO")"
[[ -n "$GLIBC_VERSION" ]] || { echo "Could not determine glibc version from: ${LIBC_INFO:-unknown}" >&2; exit 1; }
KERNEL_VERSION="${KERNEL_VERSION_OVERRIDE:-$(uname -r)}"
KERNEL_VERSION="${KERNEL_VERSION%%-*}"
version_at_least "$GLIBC_VERSION" "$MIN_GLIBC_VERSION" || { echo "glibc >= $MIN_GLIBC_VERSION is required; found $GLIBC_VERSION." >&2; exit 1; }
version_at_least "$KERNEL_VERSION" "$MIN_KERNEL_VERSION" || { echo "Linux kernel >= $MIN_KERNEL_VERSION is required; found $KERNEL_VERSION." >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "A working Docker daemon is required to build the pinned PostgreSQL server from official source." >&2; exit 1; }

mkdir -p "$OUT_DIR" "$CACHE_DIR"
OUT_DIR="$(CDPATH= cd -- "$OUT_DIR" && pwd -P)"
CACHE_DIR="$(CDPATH= cd -- "$CACHE_DIR" && pwd -P)"
WORK_PARENT="$(mktemp -d "${TMPDIR:-/tmp}/erpi-agent-builder.XXXXXX")"
WORK="$WORK_PARENT/Build Root With Spaces [relocation source]"
BUILD="$WORK/erpi-agent-env"
DL="$CACHE_DIR"
BUILDER_UV_CACHE="$CACHE_DIR/uv-cache"
BUILDER_UV_PYTHON_CACHE="$CACHE_DIR/uv-python-archives"
BUILDER_PIP_CACHE="$CACHE_DIR/pip-cache"
BUILDER_NPM_CACHE="$CACHE_DIR/npm-cache"
mkdir -p "$BUILDER_UV_CACHE" "$BUILDER_UV_PYTHON_CACHE" "$BUILDER_PIP_CACHE" "$BUILDER_NPM_CACHE"
mkdir -p "$BUILD" "$BUILD/bin" "$BUILD/runtime/python" "$BUILD/runtime/node" "$BUILD/runtime/postgres/server" "$BUILD/runtime/postgres/client" "$BUILD/runtime/node-capsules" "$BUILD/runtime/pg-delta" "$BUILD/runtime/postgrest" "$BUILD/runtime/supabase" "$BUILD/env" "$BUILD/wheelhouse" "$BUILD/licenses/source" "$BUILD/licenses/shellcheck" "$BUILD/licenses/third-party" "$BUILD/licenses/postgresql" "$BUILD/licenses/pg-delta" "$BUILD/licenses/postgrest" "$BUILD/licenses/supabase" \
  "$BUILD/state/uv-cache" "$BUILD/state/uv-python" "$BUILD/state/uv-tools" "$BUILD/state/uv-tool-bin" "$BUILD/state/pip-cache" \
  "$BUILD/state/npm-cache" "$BUILD/state/npm-global" "$BUILD/state/pycache" "$BUILD/state/postgres" "$BUILD/state/postgrest" "$BUILD/manifest" "$BUILD/scripts" "$WORK/download-extract"
ORIGINAL_BUILD_ROOT="$BUILD"
cleanup() { if (( KEEP_WORK )); then echo "Work tree retained: $WORK_PARENT"; else rm -rf "$WORK_PARENT"; fi; }
trap cleanup EXIT

log() { printf '\n==> %s\n' "$*"; }

reset_runtime_state() {
  # Mutable state is never part of the distributable payload's initial contents.
  # Tests may populate it; packaging always returns it to a pristine empty shape.
  rm -rf -- "$BUILD/state"
  mkdir -p \
    "$BUILD/state/uv-cache" \
    "$BUILD/state/uv-python" \
    "$BUILD/state/uv-tools" \
    "$BUILD/state/uv-tool-bin" \
    "$BUILD/state/pip-cache" \
    "$BUILD/state/npm-cache" \
    "$BUILD/state/npm-global" \
    "$BUILD/state/pycache" \
    "$BUILD/state/postgres" \
    "$BUILD/state/postgrest"
}
fetch() {
  local url="$1" dest="$2"
  if [[ -s "$dest" ]]; then
    echo "Using cached $(basename "$dest")"
    return
  fi
  local tmp="$dest.part.$$"
  rm -f "$tmp"
  curl --fail --location --proto '=https' --tlsv1.2 --retry 4 --retry-all-errors --connect-timeout 20 -o "$tmp" "$url"
  mv "$tmp" "$dest"
}
verify_one() {
  local file="$1" expected="$2"
  local actual
  actual="$(sha256sum "$file" | awk '{print $1}')"
  [[ "$actual" == "$expected" ]] || { echo "SHA-256 mismatch for $file" >&2; echo " expected $expected" >&2; echo " actual   $actual" >&2; exit 1; }
}
extract_single() {
  local archive="$1" pattern="$2" dest="$3"
  local scratch="$WORK/download-extract/$(basename "$dest").$$"
  rm -rf "$scratch"; mkdir -p "$scratch"
  case "$archive" in
    *.tar.gz) tar -xzf "$archive" -C "$scratch" ;;
    *.tar.xz) tar -xJf "$archive" -C "$scratch" ;;
    *) echo "Unsupported archive: $archive" >&2; exit 2 ;;
  esac
  local found
  found="$(find "$scratch" -type f -name "$pattern" -print -quit)"
  [[ -n "$found" ]] || { echo "Could not find $pattern in $archive" >&2; exit 1; }
  install -m 0755 "$found" "$dest"
  rm -rf "$scratch"
}

cp "$SELF_DIR/versions.env" "$BUILD/manifest/versions.env"
cp "$SELF_DIR/requirements.in" "$BUILD/manifest/requirements.in"
verify_one "$SELF_DIR/requirements.lock" "$PYTHON_LOCK_SHA256"
cp "$SELF_DIR/requirements.lock" "$BUILD/manifest/requirements.lock"
cp "$SELF_DIR/templates/RUNTIME-README.md" "$BUILD/README.md"
sed -i \
  -e "s/@PRODUCT_VERSION@/$PRODUCT_VERSION/g" \
  -e "s/@SOURCE_DESCRIPTION@/$SOURCE_DESCRIPTION/g" \
  -e "s/@SOURCE_COMMIT@/$SOURCE_COMMIT/g" \
  "$BUILD/README.md"
if grep -Eq '@(PRODUCT_VERSION|SOURCE_DESCRIPTION|SOURCE_COMMIT)@' "$BUILD/README.md"; then
  echo "Runtime README source-identity placeholder was not rendered." >&2
  exit 1
fi
cp "$SELF_DIR/payload/AGENTS.md.in" "$BUILD/AGENTS.md"
cp "$SELF_DIR/templates/THIRD-PARTY.md" "$BUILD/THIRD-PARTY.md"
install -m 0644 "$SELF_DIR/vendor/licenses/THIRD-PARTY-LICENSES.md" "$BUILD/licenses/third-party/THIRD-PARTY-LICENSES.md"
printf '%s\n' "$PRODUCT_VERSION" > "$BUILD/VERSION"

log "uv $UV_VERSION"
UV_AR="$DL/uv-${UV_VERSION}-x86_64-unknown-linux-gnu.tar.gz"
fetch "https://releases.astral.sh/github/uv/releases/download/${UV_VERSION}/uv-x86_64-unknown-linux-gnu.tar.gz" "$UV_AR"
verify_one "$UV_AR" "$UV_SHA256"
extract_single "$UV_AR" uv "$BUILD/bin/uv"
# uvx is deliberately a relative symlink: it is an alias for uv and survives relocation.
ln -s uv "$BUILD/bin/uvx"
"$BUILD/bin/uv" --version | grep -F "uv $UV_VERSION" >/dev/null

log "CPython $PYTHON_VERSION via pinned uv"
UV_CACHE_DIR="$BUILDER_UV_CACHE" UV_PYTHON_CACHE_DIR="$BUILDER_UV_PYTHON_CACHE" "$SELF_DIR/scripts/uv-isolated-exec.sh" "$BUILD/bin/uv" python install "$PYTHON_VERSION" --install-dir "$BUILD/runtime/python" --no-bin --managed-python
BASE_PY="$(find "$BUILD/runtime/python" -mindepth 2 -maxdepth 4 -path "*/bin/python${PYTHON_MINOR}" -print -quit)"
[[ -n "$BASE_PY" && -x "$BASE_PY" ]] || { echo "uv did not install expected Python $PYTHON_VERSION" >&2; exit 1; }
BASE_ROOT="$(CDPATH= cd -- "$(dirname -- "$BASE_PY")/.." && pwd -P)"
PYTHON_DIST_ID="$(basename -- "$BASE_ROOT")"
EXPECTED_PYTHON_DIST_ID="cpython-${PYTHON_VERSION}-linux-x86_64-gnu"
[[ "$PYTHON_DIST_ID" == "$EXPECTED_PYTHON_DIST_ID" ]] || {
  echo "Managed Python distribution identity drifted: expected $EXPECTED_PYTHON_DIST_ID; found $PYTHON_DIST_ID" >&2
  exit 1
}
[[ -f "$BASE_ROOT/BUILD" && "$(tr -d '\r\n' < "$BASE_ROOT/BUILD")" == "$PYTHON_DISTRIBUTION_BUILD" ]] || {
  echo "Managed Python build provenance does not match pinned build $PYTHON_DISTRIBUTION_BUILD." >&2
  exit 1
}
# uv creates a top-level minor-version convenience symlink for managed Python
# patch upgrades. Preserve that useful alias, but rewrite any absolute target
# that stays within this managed-Python root to a relative target before the
# bundle is moved. External absolute targets fail closed.
"$SELF_DIR/scripts/normalize-python-links.sh" "$BUILD/runtime/python"
ln -s "$PYTHON_DIST_ID" "$BUILD/runtime/python/current"

log "Relocatable Python environment"
UV_CACHE_DIR="$BUILDER_UV_CACHE" UV_PYTHON_CACHE_DIR="$BUILDER_UV_PYTHON_CACHE" UV_LINK_MODE=copy "$SELF_DIR/scripts/uv-isolated-exec.sh" "$BUILD/bin/uv" venv --relocatable --python "$BASE_PY" "$BUILD/env"
rm -f "$BUILD/env/bin/python" "$BUILD/env/bin/python3" "$BUILD/env/bin/python${PYTHON_MINOR}" "$BUILD/env/bin/.python-real"
# Keep the real interpreter as a root-relative symlink. Copying a managed Python
# executable can break $ORIGIN-relative runtime-library lookup after relocation.
ln -s "../../runtime/python/current/bin/python${PYTHON_MINOR}" "$BUILD/env/bin/.python-real"
cp "$SELF_DIR/templates/bin/python-wrapper" "$BUILD/env/bin/python"
chmod 0755 "$BUILD/env/bin/python"
ln -s python "$BUILD/env/bin/python3"
ln -s python "$BUILD/env/bin/python${PYTHON_MINOR}"
cp "$SELF_DIR/templates/scripts/repair-python.sh" "$BUILD/scripts/repair-python.sh"
chmod 0755 "$BUILD/scripts/repair-python.sh"
"$BUILD/scripts/repair-python.sh" --quiet
"$BUILD/env/bin/python" -c "import sys; assert sys.version.startswith('$PYTHON_VERSION'); print(sys.version.split()[0])"

log "Frozen Python analysis layer and offline wheelhouse"
# v1 ships the exact hashed lock captured from the first connected resolution.
# Hydration does not resolve Python dependency versions.
# Bootstrap pip only from its exact PyPI wheel, verified before any pip code executes.
# The same wheel remains in wheelhouse as part of the offline recovery set.
PIP_BOOT_CACHE="$DL/pip-26.1.2-py3-none-any.whl"
PIP_BOOT_WHEEL="$BUILD/wheelhouse/pip-26.1.2-py3-none-any.whl"
fetch "$PIP_BOOTSTRAP_WHEEL_URL" "$PIP_BOOT_CACHE"
verify_one "$PIP_BOOT_CACHE" "$PIP_BOOTSTRAP_WHEEL_SHA256"
install -m 0644 "$PIP_BOOT_CACHE" "$PIP_BOOT_WHEEL"
verify_one "$PIP_BOOT_WHEEL" "$PIP_BOOTSTRAP_WHEEL_SHA256"
UV_CACHE_DIR="$BUILDER_UV_CACHE" UV_PYTHON_CACHE_DIR="$BUILDER_UV_PYTHON_CACHE" "$SELF_DIR/scripts/uv-isolated-exec.sh" "$BUILD/bin/uv" pip install --python "$BUILD/env/bin/python" \
  --no-index --find-links "$BUILD/wheelhouse" "pip==26.1.2"
PIP_CACHE_DIR="$BUILDER_PIP_CACHE" "$BUILD/env/bin/python" -m pip download --disable-pip-version-check --require-hashes --only-binary=:all: --dest "$BUILD/wheelhouse" -r "$BUILD/manifest/requirements.lock"
UV_CACHE_DIR="$BUILDER_UV_CACHE" UV_PYTHON_CACHE_DIR="$BUILDER_UV_PYTHON_CACHE" UV_LINK_MODE=copy "$SELF_DIR/scripts/uv-isolated-exec.sh" "$BUILD/bin/uv" pip sync --python "$BUILD/env/bin/python" \
  --require-hashes --no-index --find-links "$BUILD/wheelhouse" "$BUILD/manifest/requirements.lock"
UV_CACHE_DIR="$BUILDER_UV_CACHE" UV_PYTHON_CACHE_DIR="$BUILDER_UV_PYTHON_CACHE" "$SELF_DIR/scripts/uv-isolated-exec.sh" "$BUILD/bin/uv" pip check --python "$BUILD/env/bin/python"

log "Node.js $NODE_VERSION"
NODE_AR="$DL/node-v${NODE_VERSION}-linux-x64.tar.xz"
fetch "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" "$NODE_AR"
verify_one "$NODE_AR" "$NODE_SHA256"
rm -rf "$WORK/node-extract"; mkdir -p "$WORK/node-extract"
tar -xJf "$NODE_AR" -C "$WORK/node-extract"
NODE_SRC="$WORK/node-extract/node-v${NODE_VERSION}-linux-x64"
[[ -x "$NODE_SRC/bin/node" ]] || { echo "Node archive layout unexpected" >&2; exit 1; }
rm -rf "$BUILD/runtime/node"
mv "$NODE_SRC" "$BUILD/runtime/node"
cp "$SELF_DIR/templates/bin/node-wrapper" "$BUILD/bin/node"
cp "$SELF_DIR/templates/bin/npm-wrapper" "$BUILD/bin/npm"
cp "$SELF_DIR/templates/bin/npx-wrapper" "$BUILD/bin/npx"
chmod 0755 "$BUILD/bin/node" "$BUILD/bin/npm" "$BUILD/bin/npx"
"$BUILD/bin/node" -e 'if (process.versions.node !== process.argv[1]) process.exit(1)' "$NODE_VERSION"

log "Node yaml $NODE_YAML_VERSION"
NODE_YAML_AR="$DL/yaml-${NODE_YAML_VERSION}.tgz"
fetch "https://registry.npmjs.org/yaml/-/yaml-${NODE_YAML_VERSION}.tgz" "$NODE_YAML_AR"
verify_one "$NODE_YAML_AR" "$NODE_YAML_SHA256"
rm -rf "$BUILD/runtime/node/lib/node_modules/yaml"
mkdir -p "$BUILD/runtime/node/lib/node_modules/yaml"
tar -xzf "$NODE_YAML_AR" -C "$BUILD/runtime/node/lib/node_modules/yaml" --strip-components=1
"$BUILD/env/bin/python" - "$BUILD/runtime/node/lib/node_modules/yaml/package.json" "$NODE_YAML_VERSION" <<'PY_NODE_YAML'
import json, pathlib, sys
package=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
expected=sys.argv[2]
assert package.get('name') == 'yaml'
assert package.get('version') == expected
assert package.get('license') == 'ISC'
assert package.get('engines', {}).get('node') == '>= 14.6'
PY_NODE_YAML
NODE_PATH="$BUILD/runtime/node/lib/node_modules" "$BUILD/bin/node" -e 'const Y=require("yaml"); if(require("yaml/package.json").version!==process.argv[1]||Y.parse("a: 1").a!==1) process.exit(1)' "$NODE_YAML_VERSION"

log "pg-delta $PG_DELTA_VERSION plan-only runtime"
PG_DELTA_LOCK="$SELF_DIR/vendor/pg-delta/package-lock.json"
verify_one "$PG_DELTA_LOCK" "$PG_DELTA_LOCK_SHA256"
install -m 0644 "$SELF_DIR/vendor/pg-delta/package.json" "$BUILD/runtime/pg-delta/package.json"
install -m 0644 "$PG_DELTA_LOCK" "$BUILD/runtime/pg-delta/package-lock.json"
install -m 0644 "$PG_DELTA_LOCK" "$BUILD/manifest/pg-delta-package-lock.json"
install -m 0644 "$SELF_DIR/templates/scripts/pg-delta.mjs" "$BUILD/runtime/pg-delta/plan.mjs"
install -m 0644 "$SELF_DIR/vendor/pg-delta/LICENSE" "$BUILD/licenses/pg-delta/LICENSE"
"$BUILD/env/bin/python" - "$BUILD/runtime/pg-delta/package.json" "$PG_DELTA_LOCK" "$PG_DELTA_VERSION" <<'PY_PG_DELTA_LOCK'
import json, pathlib, re, sys
package_path, lock_path = map(pathlib.Path, sys.argv[1:3])
expected = sys.argv[3]
package = json.loads(package_path.read_text(encoding='utf-8'))
lock = json.loads(lock_path.read_text(encoding='utf-8'))
assert package.get('private') is True
assert package.get('dependencies') == {'@supabase/pg-delta': expected}
assert lock.get('lockfileVersion') == 3
packages = lock.get('packages')
assert isinstance(packages, dict) and packages
assert packages[''].get('dependencies') == {'@supabase/pg-delta': expected}
direct = packages.get('node_modules/@supabase/pg-delta', {})
assert direct.get('version') == expected
assert direct.get('license') == 'MIT'
assert direct.get('engines', {}).get('node') == '>=20.0.0'
assert direct.get('bin') == {'pgdelta': 'dist/cli/bin/cli.js'}
for path, record in packages.items():
    if not path.startswith('node_modules/'):
        continue
    assert record.get('version'), (path, 'version')
    assert re.fullmatch(r'sha512-[A-Za-z0-9+/]+={0,2}', record.get('integrity','')), (path, 'integrity')
    assert str(record.get('resolved','')).startswith('https://registry.npmjs.org/'), (path, 'resolved')
    assert record.get('license'), (path, 'license')
PY_PG_DELTA_LOCK
NPM_CONFIG_CACHE="$BUILDER_NPM_CACHE" "$BUILD/bin/npm" ci --prefix "$BUILD/runtime/pg-delta" --ignore-scripts --no-audit --no-fund
"$BUILD/env/bin/python" - "$SELF_DIR/vendor/pg-delta/LICENSE" "$BUILD/runtime/pg-delta/node_modules/@supabase/pg-delta/LICENSE" <<'PY_PG_DELTA_LICENSE'
import pathlib, sys
source, installed = map(pathlib.Path, sys.argv[1:])
assert installed.is_file(), installed
assert source.read_bytes() == installed.read_bytes(), 'source-controlled pg-delta license differs from exact installed package'
PY_PG_DELTA_LICENSE
# The upstream package has apply/sync CLI commands; this environment deliberately
# exposes only the narrow plan wrapper, so npm-generated command shims are removed.
rm -rf "$BUILD/runtime/pg-delta/node_modules/.bin"
"$BUILD/runtime/node/bin/node" --check "$BUILD/runtime/pg-delta/plan.mjs"
(
  cd "$BUILD/runtime/pg-delta"
  "$BUILD/runtime/node/bin/node" --input-type=module -e 'import { createPlan, renderPlanFiles } from "@supabase/pg-delta"; import { supabase } from "@supabase/pg-delta/integrations/supabase"; if(typeof createPlan!=="function"||typeof renderPlanFiles!=="function"||typeof supabase!=="object") process.exit(1)'
)
"$BUILD/env/bin/python" - "$PG_DELTA_LOCK" "$BUILD/runtime/pg-delta/node_modules" "$BUILD/manifest/pg-delta-packages.tsv" <<'PY_PG_DELTA_PROVENANCE'
import csv, json, pathlib, sys
lock_path=pathlib.Path(sys.argv[1]); modules=pathlib.Path(sys.argv[2]); out=pathlib.Path(sys.argv[3])
packages=json.loads(lock_path.read_text(encoding='utf-8'))['packages']
rows=[]
for rel, record in sorted(packages.items()):
    if not rel.startswith('node_modules/'):
        continue
    installed=pathlib.Path(sys.argv[2]).parent/rel
    assert installed.is_dir(), (rel, 'missing after npm ci')
    rows.append((rel, record['version'], record['license'], record['resolved'], record['integrity']))
with out.open('w', encoding='utf-8', newline='') as handle:
    writer=csv.writer(handle, delimiter='\t', lineterminator='\n')
    writer.writerow(('path','version','license','resolved','integrity'))
    writer.writerows(rows)
assert rows
PY_PG_DELTA_PROVENANCE

log "Offline Node capability capsules"
mkdir -p "$BUILD/runtime/node-capsules"
for spec in \
  "postgres-${POSTGRES_JS_VERSION}.tgz:${POSTGRES_JS_SHA256}" \
  "postgres-language-server-wasm-${PGLS_WASM_VERSION}.tgz:${PGLS_WASM_SHA256}" \
  "fast-check-${FAST_CHECK_VERSION}.tgz:${FAST_CHECK_SHA256}" \
  "pure-rand-${PURE_RAND_VERSION}.tgz:${PURE_RAND_SHA256}"; do
  file="${spec%%:*}"; hash="${spec##*:}"
  verify_one "$SELF_DIR/vendor/node-capsules/$file" "$hash"
  install -m 0644 "$SELF_DIR/vendor/node-capsules/$file" "$BUILD/runtime/node-capsules/$file"
done
NODE_CAPSULE_MANIFEST="$SELF_DIR/vendor/node-capsules/manifest.json"
"$BUILD/env/bin/python" - "$NODE_CAPSULE_MANIFEST" \
  "$POSTGRES_JS_VERSION" "$POSTGRES_JS_SHA256" \
  "$PGLS_WASM_VERSION" "$PGLS_WASM_SHA256" \
  "$FAST_CHECK_VERSION" "$FAST_CHECK_SHA256" \
  "$PURE_RAND_VERSION" "$PURE_RAND_SHA256" <<'PY_NODE_MANIFEST'
import json, pathlib, re, sys
path=pathlib.Path(sys.argv[1])
values=sys.argv[2:]
expected={
    'postgres': (values[0], f'postgres-{values[0]}.tgz', values[1]),
    '@postgres-language-server/wasm': (values[2], f'postgres-language-server-wasm-{values[2]}.tgz', values[3]),
    'fast-check': (values[4], f'fast-check-{values[4]}.tgz', values[5]),
    'pure-rand': (values[6], f'pure-rand-{values[6]}.tgz', values[7]),
}
data=json.loads(path.read_text(encoding='utf-8'))
assert data.get('schema') == 1, data.get('schema')
packages=data.get('packages')
assert isinstance(packages,dict) and set(packages)==set(expected), sorted(packages or {})
for name,(version,file,sha256) in expected.items():
    record=packages[name]
    assert record.get('version') == version, (name,record.get('version'),version)
    assert record.get('file') == file, (name,record.get('file'),file)
    assert record.get('sha256') == sha256, (name,record.get('sha256'),sha256)
    assert re.fullmatch(r'sha512-[A-Za-z0-9+/]+={0,2}', record.get('integrity','')), (name,record.get('integrity'))
PY_NODE_MANIFEST
install -m 0644 "$NODE_CAPSULE_MANIFEST" "$BUILD/manifest/node-capsules.json"

log "GitHub CLI $GH_VERSION"
GH_AR="$DL/gh_${GH_VERSION}_linux_amd64.tar.gz"
fetch "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.tar.gz" "$GH_AR"
verify_one "$GH_AR" "$GH_SHA256"
extract_single "$GH_AR" gh "$BUILD/bin/gh"

log "jq $JQ_VERSION"
JQ_BIN="$DL/jq-linux-amd64-${JQ_VERSION}"
fetch "https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-linux-amd64" "$JQ_BIN"
verify_one "$JQ_BIN" "$JQ_SHA256"
install -m 0755 "$JQ_BIN" "$BUILD/bin/jq"

log "yq $YQ_VERSION"
YQ_BIN="$DL/yq_linux_amd64-${YQ_VERSION}"
fetch "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64" "$YQ_BIN"
verify_one "$YQ_BIN" "$YQ_SHA256"
install -m 0755 "$YQ_BIN" "$BUILD/bin/yq"

log "ripgrep $RIPGREP_VERSION"
RG_AR="$DL/ripgrep-${RIPGREP_VERSION}-x86_64-unknown-linux-musl.tar.gz"
fetch "https://github.com/BurntSushi/ripgrep/releases/download/${RIPGREP_VERSION}/ripgrep-${RIPGREP_VERSION}-x86_64-unknown-linux-musl.tar.gz" "$RG_AR"
verify_one "$RG_AR" "$RIPGREP_SHA256"
extract_single "$RG_AR" rg "$BUILD/bin/rg"

log "actionlint $ACTIONLINT_VERSION"
ACTION_AR="$DL/actionlint_${ACTIONLINT_VERSION}_linux_amd64.tar.gz"
fetch "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_linux_amd64.tar.gz" "$ACTION_AR"
verify_one "$ACTION_AR" "$ACTIONLINT_SHA256"
extract_single "$ACTION_AR" actionlint "$BUILD/bin/actionlint"

log "gitleaks $GITLEAKS_VERSION"
GITLEAKS_AR="$DL/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz"
fetch "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz" "$GITLEAKS_AR"
verify_one "$GITLEAKS_AR" "$GITLEAKS_SHA256"
extract_single "$GITLEAKS_AR" gitleaks "$BUILD/bin/gitleaks"

log "ShellCheck $SHELLCHECK_VERSION"
SHELLCHECK_AR="$DL/shellcheck-v${SHELLCHECK_VERSION}.linux.x86_64.tar.xz"
fetch "https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK_VERSION}/shellcheck-v${SHELLCHECK_VERSION}.linux.x86_64.tar.xz" "$SHELLCHECK_AR"
verify_one "$SHELLCHECK_AR" "$SHELLCHECK_SHA256"
extract_single "$SHELLCHECK_AR" shellcheck "$BUILD/bin/shellcheck"
SHELLCHECK_SOURCE_AR="$DL/shellcheck-v${SHELLCHECK_VERSION}-source.tar.gz"
fetch "https://github.com/koalaman/shellcheck/archive/refs/tags/v${SHELLCHECK_VERSION}.tar.gz" "$SHELLCHECK_SOURCE_AR"
verify_one "$SHELLCHECK_SOURCE_AR" "$SHELLCHECK_SOURCE_SHA256"
install -m 0644 "$SHELLCHECK_SOURCE_AR" "$BUILD/licenses/source/shellcheck-v${SHELLCHECK_VERSION}-source.tar.gz"
rm -rf "$WORK/shellcheck-source"; mkdir -p "$WORK/shellcheck-source"
tar -xzf "$SHELLCHECK_SOURCE_AR" -C "$WORK/shellcheck-source"
SHELLCHECK_SOURCE_ROOT="$WORK/shellcheck-source/shellcheck-${SHELLCHECK_VERSION}"
[[ -s "$SHELLCHECK_SOURCE_ROOT/LICENSE" && -s "$SHELLCHECK_SOURCE_ROOT/ShellCheck.cabal" ]] || {
  echo "ShellCheck source archive is missing expected license/package metadata." >&2
  exit 1
}
grep -Eiq "^version:[[:space:]]*${SHELLCHECK_VERSION}([[:space:]]|$)" "$SHELLCHECK_SOURCE_ROOT/ShellCheck.cabal" || {
  echo "ShellCheck source metadata version does not match ${SHELLCHECK_VERSION}." >&2
  exit 1
}
install -m 0644 "$SHELLCHECK_SOURCE_ROOT/LICENSE" "$BUILD/licenses/shellcheck/LICENSE"

log "Miller $MILLER_VERSION"
MILLER_AR="$DL/miller-${MILLER_VERSION}-linux-amd64.tar.gz"
fetch "https://github.com/johnkerl/miller/releases/download/v${MILLER_VERSION}/miller-${MILLER_VERSION}-linux-amd64.tar.gz" "$MILLER_AR"
verify_one "$MILLER_AR" "$MILLER_SHA256"
extract_single "$MILLER_AR" mlr "$BUILD/bin/mlr"

log "PostgREST $POSTGREST_VERSION"
POSTGREST_AR="$DL/postgrest-v${POSTGREST_VERSION}-linux-static-x86-64.tar.xz"
fetch "https://github.com/PostgREST/postgrest/releases/download/v${POSTGREST_VERSION}/postgrest-v${POSTGREST_VERSION}-linux-static-x86-64.tar.xz" "$POSTGREST_AR"
verify_one "$POSTGREST_AR" "$POSTGREST_SHA256"
extract_single "$POSTGREST_AR" postgrest "$BUILD/runtime/postgrest/postgrest"
"$BUILD/runtime/postgrest/postgrest" --version | grep -Fx "PostgREST $POSTGREST_VERSION" >/dev/null
file "$BUILD/runtime/postgrest/postgrest" | grep -F "statically linked" >/dev/null
install -m 0644 "$SELF_DIR/vendor/postgrest/LICENSE" "$BUILD/licenses/postgrest/LICENSE"

log "Supabase CLI $SUPABASE_CLI_VERSION"
SUPABASE_CLI_AR="$DL/supabase_${SUPABASE_CLI_VERSION}_linux_amd64.tar.gz"
fetch "https://github.com/supabase/cli/releases/download/v${SUPABASE_CLI_VERSION}/supabase_${SUPABASE_CLI_VERSION}_linux_amd64.tar.gz" "$SUPABASE_CLI_AR"
verify_one "$SUPABASE_CLI_AR" "$SUPABASE_CLI_SHA256"
SUPABASE_CLI_EXTRACT="$WORK/download-extract/supabase-cli"
rm -rf "$SUPABASE_CLI_EXTRACT"; mkdir -p "$SUPABASE_CLI_EXTRACT"
tar -xzf "$SUPABASE_CLI_AR" -C "$SUPABASE_CLI_EXTRACT"
mapfile -t supabase_cli_files < <(find "$SUPABASE_CLI_EXTRACT" -maxdepth 1 -type f -printf '%f\n' | LC_ALL=C sort)
[[ "${supabase_cli_files[*]}" == 'supabase supabase-go' ]] || { printf 'Unexpected Supabase CLI archive contents: %s\n' "${supabase_cli_files[*]}" >&2; exit 1; }
install -m 0755 "$SUPABASE_CLI_EXTRACT/supabase" "$BUILD/runtime/supabase/supabase"
install -m 0755 "$SUPABASE_CLI_EXTRACT/supabase-go" "$BUILD/runtime/supabase/supabase-go"
install -m 0755 "$SELF_DIR/templates/bin/supabase-wrapper" "$BUILD/bin/supabase"
install -m 0644 "$SELF_DIR/vendor/supabase/LICENSE" "$BUILD/licenses/supabase/LICENSE"
SUPABASE_GO_BINARY="$BUILD/runtime/supabase/supabase-go" "$BUILD/runtime/supabase/supabase" --version | grep -Fx "$SUPABASE_CLI_VERSION" >/dev/null
"$BUILD/runtime/supabase/supabase-go" --version | grep -Fx "$SUPABASE_CLI_VERSION" >/dev/null
file "$BUILD/runtime/supabase/supabase" | grep -F 'ELF 64-bit LSB executable, x86-64' >/dev/null
file "$BUILD/runtime/supabase/supabase-go" | grep -F 'statically linked' >/dev/null
SUPABASE_MAX_GLIBC="$(readelf --version-info "$BUILD/runtime/supabase/supabase" 2>/dev/null | grep -oE 'GLIBC_[0-9]+([.][0-9]+)+' | sort -Vu | tail -1)"
[[ -n "$SUPABASE_MAX_GLIBC" ]] || { echo 'Could not determine Supabase CLI GLIBC floor.' >&2; exit 1; }
version_at_least "$MIN_GLIBC_VERSION" "${SUPABASE_MAX_GLIBC#GLIBC_}" || {
  echo "Supabase CLI exceeds runtime GLIBC floor: $SUPABASE_MAX_GLIBC > GLIBC_$MIN_GLIBC_VERSION" >&2
  exit 1
}

log "PostgreSQL $POSTGRES_VERSION from pinned official source"
PG_SOURCE_AR="$DL/postgresql-${POSTGRES_VERSION}.tar.bz2"
PG_FLEX_RPM="$DL/${POSTGRES_FLEX_RPM_NEVRA}.rpm"
PG_CLIENT_AR="$SELF_DIR/vendor/database/postgresql-client-${POSTGRES_VERSION}-linux-x64-gnu.tar.gz"
PLCHECK_AR="$SELF_DIR/vendor/database/plpgsql-check-${PLPGSQL_CHECK_VERSION}-pg17-linux-x64-gnu.tar.gz"
fetch "$POSTGRES_SOURCE_URL" "$PG_SOURCE_AR"
verify_one "$PG_SOURCE_AR" "$POSTGRES_SOURCE_SHA256"
fetch "$POSTGRES_FLEX_RPM_URL" "$PG_FLEX_RPM"
verify_one "$PG_FLEX_RPM" "$POSTGRES_FLEX_RPM_SHA256"
verify_one "$PG_CLIENT_AR" "$POSTGRES_CLIENT_SHA256"
verify_one "$PLCHECK_AR" "$PLPGSQL_CHECK_SHA256"

# Build the ordinary PostgreSQL installation tree at a stable in-container path.
# Optional readline/zlib/ICU integrations are disabled to avoid adding host
# library requirements; this is a portability choice, not a size-minimization
# exercise. The release source tarball and build image are both pinned.
PG_BUILD_WORK="$WORK/postgres-source-build"
rm -rf "$PG_BUILD_WORK" "$BUILD/runtime/postgres/server" "$BUILD/runtime/postgres/client"
mkdir -p "$PG_BUILD_WORK" "$BUILD/runtime/postgres/server" "$BUILD/runtime/postgres/client" "$WORK/postgres-client" "$WORK/plcheck"
tar -xjf "$PG_SOURCE_AR" -C "$PG_BUILD_WORK"
install -m 0644 "$PG_FLEX_RPM" "$PG_BUILD_WORK/postgres-flex.rpm"
POSTGRES_BUILD_IMAGE_REF="${POSTGRES_BUILD_IMAGE}@sha256:${POSTGRES_BUILD_IMAGE_SHA256}"
if ! docker image inspect "$POSTGRES_BUILD_IMAGE_REF" >/dev/null 2>&1; then
  docker pull "$POSTGRES_BUILD_IMAGE_REF" >/dev/null
fi
docker run --rm --network none \
  -e POSTGRES_VERSION="$POSTGRES_VERSION" \
  -e POSTGRES_FLEX_VERSION="$POSTGRES_FLEX_VERSION" \
  -e POSTGRES_FLEX_RPM_NEVRA="$POSTGRES_FLEX_RPM_NEVRA" \
  -e HOST_UID="$(id -u)" \
  -e HOST_GID="$(id -g)" \
  -v "$PG_BUILD_WORK:/work" \
  "$POSTGRES_BUILD_IMAGE_REF" bash -lc '
    set -euo pipefail
    restore_owner() { chown -R "$HOST_UID:$HOST_GID" /work >/dev/null 2>&1 || true; }
    trap restore_owner EXIT

    flex_nevra="$(rpm -qp --qf "%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n" /work/postgres-flex.rpm)"
    [[ "$flex_nevra" == "$POSTGRES_FLEX_RPM_NEVRA" ]] || {
      echo "Pinned PostgreSQL Flex RPM identity mismatch: $flex_nevra" >&2
      exit 1
    }
    rpm -K /work/postgres-flex.rpm | grep -F "digests signatures OK" >/dev/null || {
      echo "Pinned PostgreSQL Flex RPM signature/digest verification failed." >&2
      exit 1
    }
    rpm -Uvh --nodeps --noscripts /work/postgres-flex.rpm >/dev/null
    [[ "$(flex --version)" == "flex $POSTGRES_FLEX_VERSION" ]] || {
      echo "Pinned PostgreSQL Flex executable version mismatch." >&2
      exit 1
    }
    command -v m4 >/dev/null || {
      echo "Pinned PostgreSQL build image no longer supplies m4 required by Flex." >&2
      exit 1
    }

    cd "/work/postgresql-${POSTGRES_VERSION}"
    ./configure --prefix=/usr/local/pg-build --without-readline --without-zlib --without-icu >/dev/null
    make AROPT=crsD -j2 >/dev/null
    make AROPT=crsD DESTDIR=/work/stage install >/dev/null
    make -C contrib/amcheck AROPT=crsD -j2 >/dev/null
    make -C contrib/amcheck AROPT=crsD DESTDIR=/work/stage install >/dev/null
  '
cp -a "$PG_BUILD_WORK/stage/usr/local/pg-build/." "$BUILD/runtime/postgres/server/"
install -m 0644 "$PG_BUILD_WORK/postgresql-${POSTGRES_VERSION}/COPYRIGHT" "$BUILD/licenses/postgresql/COPYRIGHT"
tar -xzf "$PG_CLIENT_AR" -C "$WORK/postgres-client"
cp -a "$WORK/postgres-client/client-payload/." "$BUILD/runtime/postgres/client/"
PG_RUNTIME_LD_LIBRARY_PATH="$BUILD/runtime/postgres/client/lib:$BUILD/runtime/postgres/server/lib"

# Fail closed if the source-built server accidentally regains the opaque native
# library bundle that motivated removal of the prebuilt server.
if find "$BUILD/runtime/postgres/server" -type f \
  \( -name 'libssl.so*' -o -name 'libcrypto.so*' -o -name 'libicu*.so*' -o -name 'libxml2.so*' -o -name 'libxslt.so*' -o -name 'liblzma.so*' -o -name 'libz.so*' -o -name 'libossp-uuid.so*' \) \
  -print -quit | grep -q .; then
  echo 'Source-built PostgreSQL server unexpectedly contains a bundled third-party shared library.' >&2
  exit 1
fi
SERVER_MAX_GLIBC="$(find "$BUILD/runtime/postgres/server" -type f -print0 | while IFS= read -r -d '' f; do
  if file "$f" | grep -q ELF; then readelf --version-info "$f" 2>/dev/null || true; fi
done | grep -oE 'GLIBC_[0-9]+([.][0-9]+)+' | sort -Vu | tail -1)"
[[ -n "$SERVER_MAX_GLIBC" ]] || { echo 'Could not determine source-built PostgreSQL GLIBC floor.' >&2; exit 1; }
version_at_least "$MIN_GLIBC_VERSION" "${SERVER_MAX_GLIBC#GLIBC_}" || {
  echo "Source-built PostgreSQL exceeds runtime GLIBC floor: $SERVER_MAX_GLIBC > GLIBC_$MIN_GLIBC_VERSION" >&2
  exit 1
}
while IFS= read -r -d '' f; do
  if file "$f" | grep -q ELF; then
    deps="$(LD_LIBRARY_PATH="$PG_RUNTIME_LD_LIBRARY_PATH" ldd "$f" 2>&1 || true)"
    if grep -Fq 'not found' <<<"$deps"; then
      echo "Unresolved PostgreSQL runtime dependency: $f" >&2
      printf '%s\n' "$deps" >&2
      exit 1
    fi
  fi
done < <(find "$BUILD/runtime/postgres/server" -type f -print0)

tar -xzf "$PLCHECK_AR" -C "$WORK/plcheck"
install -m 0644 "$SELF_DIR/vendor/pgtap/pgtap.control" "$BUILD/runtime/postgres/server/share/postgresql/extension/pgtap.control"
install -m 0644 "$SELF_DIR/vendor/pgtap/pgtap--${PGTAP_VERSION}.sql" "$BUILD/runtime/postgres/server/share/postgresql/extension/pgtap--${PGTAP_VERSION}.sql"
install -m 0644 "$WORK/plcheck/plcheck-payload/plpgsql_check.control" "$BUILD/runtime/postgres/server/share/postgresql/extension/plpgsql_check.control"
install -m 0644 "$WORK/plcheck/plcheck-payload/plpgsql_check--2.8.sql" "$BUILD/runtime/postgres/server/share/postgresql/extension/plpgsql_check--2.8.sql"
install -m 0755 "$WORK/plcheck/plcheck-payload/plpgsql_check.so" "$BUILD/runtime/postgres/server/lib/postgresql/plpgsql_check.so"
LD_LIBRARY_PATH="$PG_RUNTIME_LD_LIBRARY_PATH" "$BUILD/runtime/postgres/server/bin/postgres" --version | grep -F "$POSTGRES_VERSION" >/dev/null
LD_LIBRARY_PATH="$PG_RUNTIME_LD_LIBRARY_PATH" "$BUILD/runtime/postgres/client/bin/psql" --version | grep -F "$POSTGRES_VERSION" >/dev/null

log "Runtime control surface"
cp "$SELF_DIR/templates/activate" "$BUILD/activate"
cp "$SELF_DIR/templates/bin/agent-env" "$BUILD/bin/agent-env"
cp "$SELF_DIR/templates/scripts/doctor.py" "$BUILD/scripts/doctor.py"
cp "$SELF_DIR/templates/scripts/capabilities.py" "$BUILD/scripts/capabilities.py"
cp "$SELF_DIR/templates/scripts/postgres.py" "$BUILD/scripts/postgres.py"
cp "$SELF_DIR/templates/scripts/postgrest.py" "$BUILD/scripts/postgrest.py"
cp "$SELF_DIR/templates/scripts/pgtap.py" "$BUILD/scripts/pgtap.py"
cp "$SELF_DIR/templates/scripts/node-deps.py" "$BUILD/scripts/node-deps.py"
cp "$SELF_DIR/templates/scripts/github.sh" "$BUILD/scripts/github.sh"
cp "$SELF_DIR/templates/scripts/git-handoff.py" "$BUILD/scripts/git-handoff.py"
cp "$SELF_DIR/templates/scripts/selftest.sh" "$BUILD/scripts/selftest.sh"
cp "$SELF_DIR/templates/scripts/verify.sh" "$BUILD/scripts/verify.sh"
cp "$SELF_DIR/templates/scripts/rebuild-python.sh" "$BUILD/scripts/rebuild-python.sh"
cp "$SELF_DIR/scripts/uv-isolated-exec.sh" "$BUILD/scripts/uv-isolated-exec.sh"
cp "$SELF_DIR/templates/bin/python-wrapper" "$BUILD/scripts/python-wrapper.template"
chmod 0755 "$BUILD/bin/agent-env" "$BUILD/scripts/capabilities.py" "$BUILD/scripts/postgres.py" "$BUILD/scripts/postgrest.py" "$BUILD/scripts/pgtap.py" "$BUILD/scripts/node-deps.py" "$BUILD/scripts/github.sh" "$BUILD/scripts/git-handoff.py" "$BUILD/scripts/selftest.sh" "$BUILD/scripts/verify.sh" "$BUILD/scripts/repair-python.sh" "$BUILD/scripts/rebuild-python.sh" "$BUILD/scripts/uv-isolated-exec.sh"
mkdir -p "$BUILD/state/uv-cache" "$BUILD/state/uv-python" "$BUILD/state/uv-tools" "$BUILD/state/uv-tool-bin" "$BUILD/state/pip-cache" "$BUILD/state/npm-cache" "$BUILD/state/npm-global" "$BUILD/state/pycache" "$BUILD/state/postgres" "$BUILD/state/postgrest"

cat > "$BUILD/manifest/environment.json" <<JSON
{
  "bundle": "ERPI Agent Environment",
  "product_version": "$PRODUCT_VERSION",
  "source": {"commit": "$SOURCE_COMMIT", "description": "$SOURCE_DESCRIPTION", "base_tag": "$SOURCE_BASE_TAG", "distance": $SOURCE_DISTANCE},
  "target": "$TARGET",
  "python_lock_resolution_cutoff": "$BUILD_CUTOFF",
  "python_lock_sha256": "$PYTHON_LOCK_SHA256",
  "purpose": "Portable AI-agent execution capability layer; target repositories retain project architecture and dependency authority",
  "runtimes": {"python": "$PYTHON_VERSION", "python_distribution": "$PYTHON_DIST_ID", "node": "$NODE_VERSION"},
  "tools": {
    "uv": "$UV_VERSION",
    "gh": "$GH_VERSION",
    "jq": "$JQ_VERSION",
    "yq": "$YQ_VERSION",
    "ripgrep": "$RIPGREP_VERSION",
    "actionlint": "$ACTIONLINT_VERSION",
    "gitleaks": "$GITLEAKS_VERSION",
    "shellcheck": "$SHELLCHECK_VERSION",
    "miller": "$MILLER_VERSION"
  },
  "capabilities": {
    "postgresql": {"server": "$POSTGRES_VERSION", "server_source": "$POSTGRES_SOURCE_URL", "server_source_sha256": "$POSTGRES_SOURCE_SHA256", "server_build_image": "${POSTGRES_BUILD_IMAGE}@sha256:${POSTGRES_BUILD_IMAGE_SHA256}", "pgtap": "$PGTAP_VERSION", "plpgsql_check": "$PLPGSQL_CHECK_VERSION", "client_tools": true, "disposable_clusters": true, "pgbench": true, "dump_restore": true, "amcheck": true, "checksums": true},
    "pg_delta": {"version": "$PG_DELTA_VERSION", "supabase_cli_baseline": "$PG_DELTA_SUPABASE_CLI_BASELINE", "surface": "plan-only", "live_connections": "numeric-loopback-only"},
    "postgrest": {"version": "$POSTGREST_VERSION", "supabase_cli_baseline": "$POSTGREST_SUPABASE_CLI_BASELINE", "database_targets": "numeric-loopback-only", "http_listener": "loopback-only"},
    "supabase_cli": {"version": "$SUPABASE_CLI_VERSION", "distribution": "official-linux-amd64", "companion": "bundled-supabase-go", "credentials": "host/session", "container_runtime": "host-required-for-stack-commands"},
    "git_handoff": {"artifact_format": "git-bundle-zip-v1", "requires_host_git": true, "network": "not-required"},
    "node_capsules": {"postgres": "$POSTGRES_JS_VERSION", "@postgres-language-server/wasm": "$PGLS_WASM_VERSION", "fast-check": "$FAST_CHECK_VERSION", "pure-rand": "$PURE_RAND_VERSION"},
    "utilities": {"shellcheck": "$SHELLCHECK_VERSION", "miller": "$MILLER_VERSION", "httpx_cli": true}
  },
  "runtime_contract": {"os": "Linux", "architecture": "x86_64", "kernel_min": "$MIN_KERNEL_VERSION", "glibc_min": "$MIN_GLIBC_VERSION", "libstdcxx_symbol_min": "$MIN_GLIBCXX_SYMBOL"},
  "credentials_bundled": false,
  "github_auth": "host/session credentials; validate on demand with agent-env github",
  "mutable_paths": ["env/pyvenv.cfg", "state/"],
  "project_authority_note": "Target repositories remain authoritative for dependencies, schemas, commands, safety policy, and application architecture. Offline capsules only satisfy exact matching repository locks.",
  "python_provenance": {"version": "$PYTHON_VERSION", "distribution": "$PYTHON_DIST_ID", "build": "$PYTHON_DISTRIBUTION_BUILD", "url": "$PYTHON_DISTRIBUTION_URL", "sha256": "$PYTHON_DISTRIBUTION_SHA256"}
}
JSON

SOURCES_TSV="$BUILD/manifest/sources.tsv"
: > "$SOURCES_TSV"
source_row() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$SOURCES_TSV"; }
source_row component version url sha256
source_row uv "$UV_VERSION" "https://releases.astral.sh/github/uv/releases/download/$UV_VERSION/uv-x86_64-unknown-linux-gnu.tar.gz" "$UV_SHA256"
source_row python-build-standalone "${PYTHON_VERSION}+${PYTHON_DISTRIBUTION_BUILD}" "$PYTHON_DISTRIBUTION_URL" "$PYTHON_DISTRIBUTION_SHA256"
source_row node "$NODE_VERSION" "https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION-linux-x64.tar.xz" "$NODE_SHA256"
source_row node-yaml "$NODE_YAML_VERSION" "https://registry.npmjs.org/yaml/-/yaml-$NODE_YAML_VERSION.tgz" "$NODE_YAML_SHA256"
source_row gh "$GH_VERSION" "https://github.com/cli/cli/releases/download/v$GH_VERSION/gh_${GH_VERSION}_linux_amd64.tar.gz" "$GH_SHA256"
source_row jq "$JQ_VERSION" "https://github.com/jqlang/jq/releases/download/jq-$JQ_VERSION/jq-linux-amd64" "$JQ_SHA256"
source_row yq "$YQ_VERSION" "https://github.com/mikefarah/yq/releases/download/v$YQ_VERSION/yq_linux_amd64" "$YQ_SHA256"
source_row pip-bootstrap 26.1.2 "$PIP_BOOTSTRAP_WHEEL_URL" "$PIP_BOOTSTRAP_WHEEL_SHA256"
source_row ripgrep "$RIPGREP_VERSION" "https://github.com/BurntSushi/ripgrep/releases/download/$RIPGREP_VERSION/ripgrep-$RIPGREP_VERSION-x86_64-unknown-linux-musl.tar.gz" "$RIPGREP_SHA256"
source_row actionlint "$ACTIONLINT_VERSION" "https://github.com/rhysd/actionlint/releases/download/v$ACTIONLINT_VERSION/actionlint_${ACTIONLINT_VERSION}_linux_amd64.tar.gz" "$ACTIONLINT_SHA256"
source_row gitleaks "$GITLEAKS_VERSION" "https://github.com/gitleaks/gitleaks/releases/download/v$GITLEAKS_VERSION/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz" "$GITLEAKS_SHA256"
source_row shellcheck "$SHELLCHECK_VERSION" "https://github.com/koalaman/shellcheck/releases/download/v$SHELLCHECK_VERSION/shellcheck-v$SHELLCHECK_VERSION.linux.x86_64.tar.xz" "$SHELLCHECK_SHA256"
source_row shellcheck-source "$SHELLCHECK_VERSION" "https://github.com/koalaman/shellcheck/archive/refs/tags/v$SHELLCHECK_VERSION.tar.gz" "$SHELLCHECK_SOURCE_SHA256"
source_row miller "$MILLER_VERSION" "https://github.com/johnkerl/miller/releases/download/v$MILLER_VERSION/miller-$MILLER_VERSION-linux-amd64.tar.gz" "$MILLER_SHA256"
source_row postgrest "$POSTGREST_VERSION" "https://github.com/PostgREST/postgrest/releases/download/v$POSTGREST_VERSION/postgrest-v$POSTGREST_VERSION-linux-static-x86-64.tar.xz" "$POSTGREST_SHA256"
source_row supabase-cli "$SUPABASE_CLI_VERSION" "https://github.com/supabase/cli/releases/download/v$SUPABASE_CLI_VERSION/supabase_${SUPABASE_CLI_VERSION}_linux_amd64.tar.gz" "$SUPABASE_CLI_SHA256"
source_row postgres-server-source "$POSTGRES_VERSION" "$POSTGRES_SOURCE_URL" "$POSTGRES_SOURCE_SHA256"
source_row postgres-server-build-image manylinux_2_28_x86_64 "$POSTGRES_BUILD_IMAGE" "$POSTGRES_BUILD_IMAGE_SHA256"
source_row postgres-server-build-flex "$POSTGRES_FLEX_RPM_NEVRA" "$POSTGRES_FLEX_RPM_URL" "$POSTGRES_FLEX_RPM_SHA256"
source_row postgres-client "$POSTGRES_VERSION" "vendor/database/postgresql-client-$POSTGRES_VERSION-linux-x64-gnu.tar.gz" "$POSTGRES_CLIENT_SHA256"
source_row pgtap "$PGTAP_VERSION" "vendor/pgtap/pgtap--$PGTAP_VERSION.sql" "generated-from-$PGTAP_SOURCE_SHA256"
source_row plpgsql-check "$PLPGSQL_CHECK_VERSION" "vendor/database/plpgsql-check-$PLPGSQL_CHECK_VERSION-pg17-linux-x64-gnu.tar.gz" "$PLPGSQL_CHECK_SHA256"
source_row node-postgres "$POSTGRES_JS_VERSION" "vendor/node-capsules/postgres-$POSTGRES_JS_VERSION.tgz" "$POSTGRES_JS_SHA256"
source_row pgls-wasm "$PGLS_WASM_VERSION" "vendor/node-capsules/postgres-language-server-wasm-$PGLS_WASM_VERSION.tgz" "$PGLS_WASM_SHA256"
source_row fast-check "$FAST_CHECK_VERSION" "vendor/node-capsules/fast-check-$FAST_CHECK_VERSION.tgz" "$FAST_CHECK_SHA256"
source_row pure-rand "$PURE_RAND_VERSION" "vendor/node-capsules/pure-rand-$PURE_RAND_VERSION.tgz" "$PURE_RAND_SHA256"
source_row pg-delta-lock "$PG_DELTA_VERSION" "vendor/pg-delta/package-lock.json" "$PG_DELTA_LOCK_SHA256"
"$BUILD/env/bin/python" - "$SOURCES_TSV" <<'PY_SOURCES'
import csv, pathlib, sys
path = pathlib.Path(sys.argv[1])
rows = list(csv.reader(path.open(encoding='utf-8', newline=''), delimiter='\t'))
assert rows and rows[0] == ['component', 'version', 'url', 'sha256'], rows[:1]
assert all(len(row) == 4 and all(row) for row in rows), rows
assert b'\\t' not in path.read_bytes(), 'literal backslash-t found in sources.tsv'
PY_SOURCES

log "Normalize uv-managed Python install metadata for relocation"
mapfile -t PY_SYSCONFIG_FILES < <(find "$BASE_ROOT/lib" -maxdepth 3 -type f -name '_sysconfigdata_*.py' -print)
(( ${#PY_SYSCONFIG_FILES[@]} == 1 )) || { echo "Expected exactly one Python sysconfig-data file; found ${#PY_SYSCONFIG_FILES[@]}." >&2; printf '%s\n' "${PY_SYSCONFIG_FILES[@]}" >&2; exit 1; }
PY_SYSCONFIG="${PY_SYSCONFIG_FILES[0]}"
"$BUILD/env/bin/python" "$SELF_DIR/scripts/normalize-python-sysconfig.py" "$BASE_ROOT" "$PY_SYSCONFIG"

# After normalization, the uv-managed Python tree itself must not remember its
# install location. Fail closed if a future uv/Python distribution adds another
# install-prefix-bearing file that we have not deliberately handled.
if grep -r -a -F -l "$BASE_ROOT" "$BASE_ROOT" > "$WORK/python-prefix-residue.txt" 2>/dev/null; then
  echo "Unexpected Python install-prefix residue after sysconfig normalization:" >&2
  cat "$WORK/python-prefix-residue.txt" >&2
  exit 1
fi

log "Sanitize generated bytecode and mutable state"
find "$BUILD" -type d -name __pycache__ -prune -exec rm -rf {} +
find "$BUILD" -type f \( -name '*.pyc' -o -name '*.pyo' \) -delete
# Caches are useful during tests but are not required for first-use operation; wheelhouse is the recovery source.
# Remove the entire mutable tree so dotfiles, symlinks, and path-bearing cache metadata cannot leak into the artifact.
reset_runtime_state

log "Portability gate: reject original build-root residue"
# pyvenv.cfg is the one declared relocation-mutable file. Before the first move
# it correctly names the current absolute base-Python path, so exclude it here.
# After relocation it is repaired and then included in the stale-path scan.
if grep -r -a -F -l --exclude='pyvenv.cfg' "$ORIGINAL_BUILD_ROOT" "$BUILD" > "$WORK/residue.txt" 2>/dev/null; then
  echo "Absolute original build path remains in portable payload:" >&2
  cat "$WORK/residue.txt" >&2
  exit 1
fi

log "Portability gate: no absolute symlinks"
absolute_links=0
while IFS= read -r -d '' link; do
  target="$(readlink "$link")"
  if [[ "$target" == /* ]]; then echo "$link -> $target" >&2; absolute_links=1; fi
done < <(find "$BUILD" -type l -print0)
(( absolute_links == 0 )) || { echo "Absolute symlink(s) found." >&2; exit 1; }

log "Relocation torture test"
MOVED="$WORK_PARENT/Second Location – spaces and unicode/deep/nested/relocation/target/erpi-agent-env"
mkdir -p "$(dirname -- "$MOVED")"
mv "$BUILD" "$MOVED"
BUILD="$MOVED"
"$BUILD/scripts/repair-python.sh" --quiet
"$BUILD/bin/agent-env" selftest

log "Offline Python destruction/rebuild proof"
"$BUILD/bin/agent-env" rebuild-python >/dev/null
"$BUILD/bin/agent-env" selftest >/dev/null

# Scan the moved tree again for the original source root, now including pyvenv.cfg.
# Relocation repair must have removed the old location completely.
if grep -r -a -F -l "$ORIGINAL_BUILD_ROOT" "$BUILD" > "$WORK/residue-after-move.txt" 2>/dev/null; then
  echo "Relocation left original path residue:" >&2
  cat "$WORK/residue-after-move.txt" >&2
  exit 1
fi

log "Reset mutable state for distribution"
# Relocation/self-test/rebuild deliberately populate state/ with bytecode and caches.
# None of that state is authoritative, and .pyc co_filename/cache metadata can encode
# the path where the tests ran. Ship an empty mutable state tree instead.
reset_runtime_state
state_residue="$(find "$BUILD/state" -mindepth 1 \( -type f -o -type l \) -print -quit)"
if [[ -n "$state_residue" ]]; then
  echo "Mutable state was not pristine before packaging: $state_residue" >&2
  exit 1
fi

# uv creates zero-byte lock files with permissive modes. They are retained for
# uv semantics but normalized so the immutable archive contains no writable-by-
# group/world regular files.
for lock_file in "$BUILD/env/.lock" "$BUILD/runtime/python/.lock"; do
  [[ ! -e "$lock_file" ]] || chmod 0644 "$lock_file"
done
writable_payload="$(find "$BUILD" -type f ! -path "$BUILD/state/*" -perm /022 -print -quit)"
if [[ -n "$writable_payload" ]]; then
  echo "Immutable payload contains a group/world-writable regular file: $writable_payload" >&2
  exit 1
fi

# pyvenv.cfg is repaired on first Python invocation. Ship a deterministic
# sentinel instead of leaking the random builder path into the archive.
PYVENV_CFG="$BUILD/env/pyvenv.cfg"
awk '
  /^home = / { print "home = __ERPI_AGENT_RELOCATE__/runtime/python/current/bin"; next }
  { print }
' "$PYVENV_CFG" > "$PYVENV_CFG.tmp"
mv "$PYVENV_CFG.tmp" "$PYVENV_CFG"
if grep -r -a -F -l "$BUILD" "$BUILD" > "$WORK/current-build-residue.txt" 2>/dev/null; then
  echo "Current random build path remains in distribution payload:" >&2
  cat "$WORK/current-build-residue.txt" >&2
  exit 1
fi

log "Immutable payload checksum manifest"
cd "$BUILD"
find . -type l ! -path './state/*' -printf '%p\t%l\n' | LC_ALL=C sort > manifest/SYMLINKS
find . -type f \
  ! -path './state/*' \
  ! -path './env/pyvenv.cfg' \
  ! -path './manifest/SHA256SUMS' \
  -print0 | LC_ALL=C sort -z | xargs -0 sha256sum > manifest/SHA256SUMS
"$BUILD/bin/agent-env" verify >/dev/null

log "Archive/extract proof"
ARTIFACT="$OUT_DIR/${ARTIFACT_STEM}.tar.gz"
TMP_ART="$ARTIFACT.part.$$"
rm -f "$TMP_ART" "$ARTIFACT"
# Normalize ordering, timestamps, owner metadata, and gzip headers so the
# same accepted payload produces identical archive bytes.
write_archive() {
  local dest="$1"
  tar --sort=name --format=gnu --numeric-owner --owner=0 --group=0 \
    --mtime="$ARCHIVE_MTIME" --clamp-mtime \
    -cf - -C "$(dirname -- "$BUILD")" "$(basename -- "$BUILD")" | gzip -n > "$dest"
}
write_archive "$TMP_ART"
REPRO_ART="$WORK_PARENT/reproducibility-proof.tar.gz"
write_archive "$REPRO_ART"
[[ "$(sha256sum "$TMP_ART" | awk '{print $1}')" == "$(sha256sum "$REPRO_ART" | awk '{print $1}')" ]] || {
  echo "Archive packaging is not deterministic for the accepted payload." >&2
  exit 1
}
mv "$TMP_ART" "$ARTIFACT"
(cd "$OUT_DIR" && sha256sum "$(basename -- "$ARTIFACT")") > "$ARTIFACT.sha256"
(cd "$OUT_DIR" && sha256sum -c "$(basename -- "$ARTIFACT.sha256")") >/dev/null

EXTRACT_TEST="$WORK_PARENT/final extraction proof"
mkdir -p "$EXTRACT_TEST"
tar -xzf "$ARTIFACT" -C "$EXTRACT_TEST"
EXTRACTED="$EXTRACT_TEST/erpi-agent-env"
"$EXTRACTED/bin/agent-env" selftest >/dev/null
# The archive was created from $BUILD. First-use repair in the extracted copy
# must remove that former absolute location everywhere, including pyvenv.cfg.
if grep -r -a -F -l "$BUILD" "$EXTRACTED" > "$WORK/residue-after-extract.txt" 2>/dev/null; then
  echo "Fresh extraction retained its archive-build location:" >&2
  cat "$WORK/residue-after-extract.txt" >&2
  exit 1
fi
"$EXTRACTED/bin/agent-env" verify >/dev/null

log "Build complete"
echo "Product version: $PRODUCT_VERSION"
echo "Source: $SOURCE_DESCRIPTION"
echo "Source commit: $SOURCE_COMMIT"
echo "$ARTIFACT"
echo "$ARTIFACT.sha256"
echo "Size: $(du -h "$ARTIFACT" | awk '{print $1}')"
