#!/usr/bin/env bash
set -euo pipefail
umask 022

SELF_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck disable=SC1091
source "$SELF_DIR/versions.env"
# shellcheck disable=SC1091
source "$SELF_DIR/scripts/build-common.sh"

KEEP_WORK=0
ARTIFACT=""
usage() {
  cat <<'USAGE'
Usage: ./accept.sh [ARCHIVE.tar.gz] [--keep-work]

Qualify an already-built ERPI Agent Environment archive. When ARCHIVE is omitted,
exactly one dist/*.tar.gz artifact must exist.
USAGE
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep-work) KEEP_WORK=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
    *) [[ -z "$ARTIFACT" ]] || { echo 'Only one archive may be supplied.' >&2; exit 2; }; ARTIFACT="$1"; shift ;;
  esac
done

for cmd in bash tar gzip sha256sum grep find mktemp mv mkdir dirname basename readlink cat; do build_need "$cmd"; done
if [[ -z "$ARTIFACT" ]]; then
  mapfile -t artifacts < <(compgen -G "$SELF_DIR/dist/*.tar.gz" || true)
  ((${#artifacts[@]} == 1)) || {
    echo "Expected exactly one dist/*.tar.gz artifact; found ${#artifacts[@]}. Supply the archive path explicitly." >&2
    exit 2
  }
  ARTIFACT="${artifacts[0]}"
fi
ARTIFACT="$(readlink -f "$ARTIFACT")"
[[ -f "$ARTIFACT" ]] || { echo "Archive not found: $ARTIFACT" >&2; exit 1; }
SIDECAR="$ARTIFACT.sha256"
[[ -f "$SIDECAR" ]] || { echo "Archive checksum sidecar missing: $SIDECAR" >&2; exit 1; }
(cd "$(dirname -- "$ARTIFACT")" && sha256sum -c "$(basename -- "$SIDECAR")") >/dev/null

WORK_PARENT="$(mktemp -d "${TMPDIR:-/tmp}/erpi-agent-accept.XXXXXX")"
cleanup() { if (( KEEP_WORK )); then echo "Acceptance work tree retained: $WORK_PARENT"; else rm -rf "$WORK_PARENT"; fi; }
trap cleanup EXIT

EXTRACT_ROOT="$WORK_PARENT/original extraction"
mkdir -p "$EXTRACT_ROOT"
build_run_logged "Extract accepted archive" "$WORK_PARENT/extract.log" tar -xzf "$ARTIFACT" -C "$EXTRACT_ROOT"
RUNTIME="$EXTRACT_ROOT/erpi-agent-env"
[[ -x "$RUNTIME/bin/agent-env" ]] || { echo 'Archive does not contain expected erpi-agent-env runtime root.' >&2; exit 1; }
[[ "$(cat "$RUNTIME/VERSION")" == "$PRODUCT_VERSION" ]] || {
  echo "Archive product version $(cat "$RUNTIME/VERSION") does not match source PRODUCT_VERSION $PRODUCT_VERSION." >&2
  exit 1
}
"$RUNTIME/bin/agent-env" verify >/dev/null

REPRO="$WORK_PARENT/reproduced.tar.gz"
build_run_logged "Reproduce archive bytes" "$WORK_PARENT/reproduce.log" \
  build_write_archive "$RUNTIME" "$REPRO" "$ARCHIVE_MTIME"
ORIGINAL_SHA="$(build_sha256 "$ARTIFACT")"
REPRO_SHA="$(build_sha256 "$REPRO")"
[[ "$ORIGINAL_SHA" == "$REPRO_SHA" ]] || {
  echo 'Archive packaging is not deterministic for the accepted payload.' >&2
  echo " original $ORIGINAL_SHA" >&2
  echo " reproduced $REPRO_SHA" >&2
  exit 1
}

ORIGINAL_RUNTIME="$RUNTIME"
MOVED="$WORK_PARENT/Second Location – spaces and unicode/deep/nested/relocation/target/erpi-agent-env"
mkdir -p "$(dirname -- "$MOVED")"
mv "$RUNTIME" "$MOVED"
RUNTIME="$MOVED"

build_run_logged "Full runtime integration self-test" "$WORK_PARENT/runtime-selftest.log" \
  "$RUNTIME/bin/agent-env" selftest

build_run_logged "Offline Python destruction/rebuild proof" "$WORK_PARENT/python-rebuild.log" \
  "$RUNTIME/bin/agent-env" rebuild-python

check_relocation_residue() {
  local output="$1" rc=0
  if grep -r -a -F -l "$ORIGINAL_RUNTIME" "$RUNTIME" >"$output" 2>/dev/null; then
    echo 'Hostile relocation retained the original extraction path:' >&2
    cat "$output" >&2
    return 1
  else
    rc=$?
    [[ "$rc" == 1 ]] || return "$rc"
  fi
}
build_run_logged "Scan hostile relocation for stale paths" "$WORK_PARENT/relocation-scan.log" \
  check_relocation_residue "$WORK_PARENT/relocation-residue.txt"
"$RUNTIME/bin/agent-env" verify >/dev/null

printf '\nAcceptance complete\n'
printf 'Product version: %s\n' "$PRODUCT_VERSION"
printf 'Archive: %s\n' "$ARTIFACT"
printf 'SHA-256: %s\n' "$ORIGINAL_SHA"
build_timing_summary
