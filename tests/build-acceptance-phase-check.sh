#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
BUILD="$ROOT/build.sh"
ACCEPT="$ROOT/accept.sh"
COMMON="$ROOT/scripts/build-common.sh"
REBUILD="$ROOT/templates/scripts/rebuild-python.sh"
PG_RECIPE="$ROOT/scripts/postgres-server-build.sh"
ACCEPT_WORKFLOW="$ROOT/.github/workflows/accept-runtime.yml"
PUBLISH="$ROOT/.github/workflows/publish-release.yml"
REPRO="$ROOT/.github/workflows/reproduce-distribution.yml"

for file in "$BUILD" "$ACCEPT" "$COMMON" "$REBUILD" "$PG_RECIPE" "$ACCEPT_WORKFLOW" "$PUBLISH" "$REPRO"; do
  [[ -s "$file" ]] || { echo "Required phase source missing: $file" >&2; exit 1; }
done

# Construction must not silently perform release-grade behavioral acceptance.
! grep -F 'agent-env" selftest' "$BUILD" >/dev/null
! grep -F 'rebuild-python' "$BUILD" >/dev/null
! grep -F 'Relocation torture test' "$BUILD" >/dev/null
! grep -F 'Archive/extract proof' "$BUILD" >/dev/null
[[ "$(grep -Fc 'build_write_archive "$BUILD"' "$BUILD")" == 1 ]] || {
  echo 'Normal build must package the distribution exactly once.' >&2
  exit 1
}

# Acceptance owns one full suite, one Python-only recovery proof, hostile relocation,
# and byte-for-byte archive reproduction.
[[ "$(grep -Fc 'agent-env" selftest' "$ACCEPT")" == 1 ]] || {
  echo 'Acceptance must run the full runtime self-test exactly once.' >&2
  exit 1
}
[[ "$(grep -Fc 'agent-env" rebuild-python' "$ACCEPT")" == 1 ]] || {
  echo 'Acceptance must run the offline Python rebuild exactly once.' >&2
  exit 1
}
grep -F 'build_write_archive "$RUNTIME" "$REPRO" "$ARCHIVE_MTIME"' "$ACCEPT" >/dev/null
grep -F 'Second Location – spaces and unicode' "$ACCEPT" >/dev/null
! grep -F 'selftest.sh' "$REBUILD" >/dev/null
grep -F 'python-smoke.sh' "$REBUILD" >/dev/null
grep -F 'normalize-python-metadata.py' "$REBUILD" >/dev/null

# PostgreSQL source compilation is a cache-miss operation with exact recipe/input identity.
grep -F 'PG_RECIPE_SHA256="$(build_sha256 "$PG_RECIPE")"' "$BUILD" >/dev/null
grep -F 'PG_DERIVED_KEY=' "$BUILD" >/dev/null
grep -F 'POSTGRES_SOURCE_SHA256' "$BUILD" >/dev/null
grep -F 'POSTGRES_FLEX_RPM_SHA256' "$BUILD" >/dev/null
grep -F 'POSTGRES_BUILD_IMAGE_SHA256' "$BUILD" >/dev/null
grep -F 'Docker is required for a cold PostgreSQL derived-cache miss.' "$BUILD" >/dev/null
grep -F 'ERPI_BUILD_JOBS="$BUILD_JOBS"' "$BUILD" >/dev/null
! grep -R -nF 'make AROPT=crsD -j2' "$BUILD" "$PG_RECIPE" "$ROOT/scripts/rebuild-qualified-database-assets.sh"
grep -F 'make AROPT=crsD -j"$ERPI_BUILD_JOBS"' "$PG_RECIPE" >/dev/null

# Long-running phases use one shared heartbeat/timing mechanism.
grep -F 'build_run_logged()' "$COMMON" >/dev/null
grep -F 'still running' "$COMMON" >/dev/null
grep -F 'build_timing_summary()' "$COMMON" >/dev/null
grep -F 'build_run_logged "Compress distribution archive"' "$BUILD" >/dev/null
grep -F 'build_run_logged "Full runtime integration self-test"' "$ACCEPT" >/dev/null
grep -F 'build_run_logged "Offline Python destruction/rebuild proof"' "$ACCEPT" >/dev/null

# CI runs construction and acceptance as explicit phases and retains the exact accepted bytes.
build_line="$(grep -nF 'run: ./build.sh' "$ACCEPT_WORKFLOW" | cut -d: -f1)"
accept_line="$(grep -nF 'run: ./accept.sh' "$ACCEPT_WORKFLOW" | cut -d: -f1)"
[[ -n "$build_line" && -n "$accept_line" && "$build_line" -lt "$accept_line" ]] || {
  echo 'Accept runtime must build before accepting the artifact.' >&2
  exit 1
}
grep -F 'dist/*.tar.gz' "$ACCEPT_WORKFLOW" >/dev/null

# Publication consumes acceptance evidence; independent reproduction never mutates releases.
grep -F 'gh run download "$run_id"' "$PUBLISH" >/dev/null
! grep -F 'run: ./build.sh' "$PUBLISH" >/dev/null
! grep -F 'gh workflow run' "$PUBLISH" >/dev/null
grep -F 'name: Reproduce distribution' "$REPRO" >/dev/null
grep -F 'run: ./build.sh' "$REPRO" >/dev/null
grep -F 'run: ./accept.sh' "$REPRO" >/dev/null
! grep -F 'gh release upload' "$REPRO" >/dev/null
! grep -F 'gh release edit' "$REPRO" >/dev/null

echo 'Build/acceptance phase checks passed.'
