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

Build Magnet Agent Environment ${BUNDLE_VERSION} for ${TARGET}.
Requires an internet-connected Linux x86-64 glibc host. No sudo is used.
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

need() { command -v "$1" >/dev/null 2>&1 || { echo "Required build command missing: $1" >&2; exit 1; }; }
for cmd in bash curl tar xz sha256sum find grep sed awk mktemp cp mv ln chmod install readlink xargs sort du ldd uname; do need "$cmd"; done
TAR_VERSION="$(tar --version 2>/dev/null || true)"
grep -q 'GNU tar' <<<"$TAR_VERSION" || { echo "GNU tar is required by this builder." >&2; exit 1; }
[[ "$(uname -s)" == Linux ]] || { echo "Builder target is Linux only." >&2; exit 1; }
[[ "$(uname -m)" == x86_64 ]] || { echo "Builder target is x86_64 only; found $(uname -m)." >&2; exit 1; }
LIBC_INFO="$(getconf GNU_LIBC_VERSION 2>/dev/null || true)"
if [[ -z "$LIBC_INFO" ]]; then
  LIBC_INFO="$(ldd --version 2>&1 || true)"
fi
grep -Eqi 'glibc|GNU C Library|GNU libc' <<<"$LIBC_INFO" || { echo "A glibc-based build host is required. Detected: ${LIBC_INFO:-unknown}" >&2; exit 1; }

mkdir -p "$OUT_DIR" "$CACHE_DIR"
OUT_DIR="$(CDPATH= cd -- "$OUT_DIR" && pwd -P)"
CACHE_DIR="$(CDPATH= cd -- "$CACHE_DIR" && pwd -P)"
WORK_PARENT="$(mktemp -d "${TMPDIR:-/tmp}/magnet-agent-builder.XXXXXX")"
WORK="$WORK_PARENT/Build Root With Spaces [relocation source]"
BUILD="$WORK/magnet-agent-env"
DL="$CACHE_DIR"
mkdir -p "$BUILD" "$BUILD/bin" "$BUILD/runtime/python" "$BUILD/runtime/node" "$BUILD/env" "$BUILD/wheelhouse" \
  "$BUILD/state/uv-cache" "$BUILD/state/uv-python" "$BUILD/state/uv-tools" "$BUILD/state/uv-tool-bin" "$BUILD/state/pip-cache" \
  "$BUILD/state/npm-cache" "$BUILD/state/npm-global" "$BUILD/state/pycache" "$BUILD/manifest" "$BUILD/scripts" "$WORK/download-extract"
ORIGINAL_BUILD_ROOT="$BUILD"
cleanup() { if (( KEEP_WORK )); then echo "Work tree retained: $WORK_PARENT"; else rm -rf "$WORK_PARENT"; fi; }
trap cleanup EXIT

log() { printf '\n==> %s\n' "$*"; }
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
    *) echo "Unsupported archive: $archive" >&2; exit 1 ;;
  esac
  local found
  found="$(find "$scratch" -type f -name "$pattern" -print -quit)"
  [[ -n "$found" ]] || { echo "Could not find $pattern in $archive" >&2; exit 1; }
  install -m 0755 "$found" "$dest"
  rm -rf "$scratch"
}

cp "$SELF_DIR/versions.env" "$BUILD/manifest/versions.env"
cp "$SELF_DIR/requirements.in" "$BUILD/manifest/requirements.in"
cp "$SELF_DIR/templates/RUNTIME-README.md" "$BUILD/README.md"
cp "$SELF_DIR/templates/AGENTS.md" "$BUILD/AGENTS.md"
cp "$SELF_DIR/templates/THIRD-PARTY.md" "$BUILD/THIRD-PARTY.md"
printf '%s\n' "$BUNDLE_VERSION" > "$BUILD/VERSION"

log "uv $UV_VERSION"
UV_AR="$DL/uv-${UV_VERSION}-x86_64-unknown-linux-gnu.tar.gz"
fetch "https://releases.astral.sh/github/uv/releases/download/${UV_VERSION}/uv-x86_64-unknown-linux-gnu.tar.gz" "$UV_AR"
verify_one "$UV_AR" "$UV_SHA256"
extract_single "$UV_AR" uv "$BUILD/bin/uv"
# uvx is deliberately a relative symlink: it is an alias for uv and survives relocation.
ln -s uv "$BUILD/bin/uvx"
"$BUILD/bin/uv" --version | grep -F "uv $UV_VERSION" >/dev/null

log "CPython $PYTHON_VERSION via pinned uv"
UV_CACHE_DIR="$BUILD/state/uv-cache" "$BUILD/bin/uv" python install "$PYTHON_VERSION" --install-dir "$BUILD/runtime/python" --no-bin --managed-python
BASE_PY="$(find "$BUILD/runtime/python" -mindepth 2 -maxdepth 4 -path "*/bin/python${PYTHON_MINOR}" -print -quit)"
[[ -n "$BASE_PY" && -x "$BASE_PY" ]] || { echo "uv did not install expected Python $PYTHON_VERSION" >&2; exit 1; }
BASE_ROOT="$(CDPATH= cd -- "$(dirname -- "$BASE_PY")/.." && pwd -P)"
PYTHON_DIST_ID="$(basename -- "$BASE_ROOT")"
ln -s "$PYTHON_DIST_ID" "$BUILD/runtime/python/current"

log "Relocatable Python environment"
UV_CACHE_DIR="$BUILD/state/uv-cache" UV_LINK_MODE=copy "$BUILD/bin/uv" venv --relocatable --python "$BASE_PY" "$BUILD/env"
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

log "Locked Python analysis layer and offline wheelhouse"
UV_CACHE_DIR="$BUILD/state/uv-cache" "$BUILD/bin/uv" pip compile "$BUILD/manifest/requirements.in" \
  --python "$BUILD/env/bin/python" --python-version "$PYTHON_VERSION" --generate-hashes --no-header --no-annotate --exclude-newer "$BUILD_CUTOFF" \
  --output-file "$BUILD/manifest/requirements.lock"
# Bootstrap pip only long enough to download the exact hashed wheel set. The final sync is from wheelhouse only.
UV_CACHE_DIR="$BUILD/state/uv-cache" "$BUILD/bin/uv" pip install --python "$BUILD/env/bin/python" "pip==26.1.2"
"$BUILD/env/bin/python" -m pip download --disable-pip-version-check --require-hashes --only-binary=:all: --dest "$BUILD/wheelhouse" -r "$BUILD/manifest/requirements.lock"
UV_CACHE_DIR="$BUILD/state/uv-cache" UV_LINK_MODE=copy "$BUILD/bin/uv" pip sync --python "$BUILD/env/bin/python" \
  --require-hashes --no-index --find-links "$BUILD/wheelhouse" "$BUILD/manifest/requirements.lock"
UV_CACHE_DIR="$BUILD/state/uv-cache" "$BUILD/bin/uv" pip check --python "$BUILD/env/bin/python"

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

log "Runtime control surface"
cp "$SELF_DIR/templates/activate" "$BUILD/activate"
cp "$SELF_DIR/templates/bin/agent-env" "$BUILD/bin/agent-env"
cp "$SELF_DIR/templates/scripts/doctor.py" "$BUILD/scripts/doctor.py"
cp "$SELF_DIR/templates/scripts/github.sh" "$BUILD/scripts/github.sh"
cp "$SELF_DIR/templates/scripts/selftest.sh" "$BUILD/scripts/selftest.sh"
cp "$SELF_DIR/templates/scripts/verify.sh" "$BUILD/scripts/verify.sh"
cp "$SELF_DIR/templates/scripts/rebuild-python.sh" "$BUILD/scripts/rebuild-python.sh"
cp "$SELF_DIR/templates/bin/python-wrapper" "$BUILD/scripts/python-wrapper.template"
chmod 0755 "$BUILD/bin/agent-env" "$BUILD/scripts/github.sh" "$BUILD/scripts/selftest.sh" "$BUILD/scripts/verify.sh" "$BUILD/scripts/repair-python.sh" "$BUILD/scripts/rebuild-python.sh"
mkdir -p "$BUILD/state/uv-cache" "$BUILD/state/uv-python" "$BUILD/state/uv-tools" "$BUILD/state/uv-tool-bin" "$BUILD/state/pip-cache" "$BUILD/state/npm-cache" "$BUILD/state/npm-global" "$BUILD/state/pycache"

cat > "$BUILD/manifest/environment.json" <<JSON
{
  "bundle": "Magnet Agent Environment",
  "bundle_version": "$BUNDLE_VERSION",
  "target": "$TARGET",
  "build_cutoff": "$BUILD_CUTOFF",
  "purpose": "Portable AI-agent execution capability layer; external to Magnet Photos project architecture",
  "runtimes": {"python": "$PYTHON_VERSION", "python_distribution": "$PYTHON_DIST_ID", "node": "$NODE_VERSION"},
  "tools": {
    "uv": "$UV_VERSION",
    "gh": "$GH_VERSION",
    "jq": "$JQ_VERSION",
    "yq": "$YQ_VERSION",
    "ripgrep": "$RIPGREP_VERSION",
    "actionlint": "$ACTIONLINT_VERSION",
    "gitleaks": "$GITLEAKS_VERSION"
  },
  "credentials_bundled": false,
  "github_auth": "host/session credentials; validate on demand with agent-env github",
  "mutable_paths": ["env/pyvenv.cfg", "state/"],
  "project_authority_note": "Magnet Photos repository Makefile/package-lock remain authoritative for project tooling such as Supabase and PGLS."
}
JSON

cat > "$BUILD/manifest/sources.tsv" <<SOURCES
component\tversion\turl\tsha256
uv\t$UV_VERSION\thttps://releases.astral.sh/github/uv/releases/download/$UV_VERSION/uv-x86_64-unknown-linux-gnu.tar.gz\t$UV_SHA256
node\t$NODE_VERSION\thttps://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION-linux-x64.tar.xz\t$NODE_SHA256
gh\t$GH_VERSION\thttps://github.com/cli/cli/releases/download/v$GH_VERSION/gh_${GH_VERSION}_linux_amd64.tar.gz\t$GH_SHA256
jq\t$JQ_VERSION\thttps://github.com/jqlang/jq/releases/download/jq-$JQ_VERSION/jq-linux-amd64\t$JQ_SHA256
yq\t$YQ_VERSION\thttps://github.com/mikefarah/yq/releases/download/v$YQ_VERSION/yq_linux_amd64\t$YQ_SHA256
ripgrep\t$RIPGREP_VERSION\thttps://github.com/BurntSushi/ripgrep/releases/download/$RIPGREP_VERSION/ripgrep-$RIPGREP_VERSION-x86_64-unknown-linux-musl.tar.gz\t$RIPGREP_SHA256
actionlint\t$ACTIONLINT_VERSION\thttps://github.com/rhysd/actionlint/releases/download/v$ACTIONLINT_VERSION/actionlint_${ACTIONLINT_VERSION}_linux_amd64.tar.gz\t$ACTIONLINT_SHA256
gitleaks\t$GITLEAKS_VERSION\thttps://github.com/gitleaks/gitleaks/releases/download/v$GITLEAKS_VERSION/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz\t$GITLEAKS_SHA256
SOURCES

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
# Caches are useful during build but are not required for first-use operation; wheelhouse is the recovery source.
rm -rf "$BUILD/state/uv-cache"/* "$BUILD/state/uv-python"/* "$BUILD/state/uv-tools"/* "$BUILD/state/uv-tool-bin"/* "$BUILD/state/pip-cache"/* "$BUILD/state/npm-cache"/* "$BUILD/state/npm-global"/* "$BUILD/state/pycache"/* 2>/dev/null || true

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
MOVED="$WORK_PARENT/Second Location – spaces and unicode/deep/nested/relocation/target/magnet-agent-env"
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
ARTIFACT="$OUT_DIR/magnet-agent-env-linux-x64-v${BUNDLE_VERSION}.tar.gz"
TMP_ART="$ARTIFACT.part.$$"
rm -f "$TMP_ART" "$ARTIFACT"
# Normalize owner metadata; preserve modes and symlinks.
tar --numeric-owner --owner=0 --group=0 -czf "$TMP_ART" -C "$(dirname -- "$BUILD")" "$(basename -- "$BUILD")"
mv "$TMP_ART" "$ARTIFACT"
(cd "$OUT_DIR" && sha256sum "$(basename -- "$ARTIFACT")") > "$ARTIFACT.sha256"
(cd "$OUT_DIR" && sha256sum -c "$(basename -- "$ARTIFACT.sha256")") >/dev/null

EXTRACT_TEST="$WORK_PARENT/final extraction proof"
mkdir -p "$EXTRACT_TEST"
tar -xzf "$ARTIFACT" -C "$EXTRACT_TEST"
EXTRACTED="$EXTRACT_TEST/magnet-agent-env"
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
echo "$ARTIFACT"
echo "$ARTIFACT.sha256"
echo "Size: $(du -h "$ARTIFACT" | awk '{print $1}')"
