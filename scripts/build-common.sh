#!/usr/bin/env bash
# Shared connected-builder primitives. This file is sourced; callers own set -euo pipefail.

BUILD_PROGRESS_INTERVAL_SECONDS="${ERPI_PROGRESS_INTERVAL:-15}"
BUILD_TIMING_NAMES=()
BUILD_TIMING_SECONDS=()

build_need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Required build command missing: $1" >&2
    return 1
  }
}

build_sha256() {
  sha256sum "$1" | awk '{print $1}'
}

build_verify_sha256() {
  local file="$1" expected="$2" actual
  [[ -f "$file" ]] || {
    echo "Required artifact missing: $file" >&2
    return 1
  }
  actual="$(build_sha256 "$file")"
  [[ "$actual" == "$expected" ]] || {
    echo "SHA-256 mismatch for $file" >&2
    echo " expected $expected" >&2
    echo " actual   $actual" >&2
    return 1
  }
}

build_record_timing() {
  BUILD_TIMING_NAMES+=("$1")
  BUILD_TIMING_SECONDS+=("$2")
}

build_run_logged() {
  local name="$1" log_file="$2"
  shift 2
  local start="$SECONDS" status=0 elapsed pid interval="$BUILD_PROGRESS_INTERVAL_SECONDS"
  [[ "$interval" =~ ^[1-9][0-9]*$ ]] || {
    echo "ERPI_PROGRESS_INTERVAL must be a positive integer; found: $interval" >&2
    return 2
  }
  mkdir -p "$(dirname -- "$log_file")"
  : > "$log_file"
  printf '    -> %s\n' "$name" >&2
  ( "$@" ) >"$log_file" 2>&1 &
  pid=$!
  local next_heartbeat=$interval
  while kill -0 "$pid" 2>/dev/null; do
    sleep 1 || true
    elapsed=$((SECONDS - start))
    if kill -0 "$pid" 2>/dev/null && (( elapsed >= next_heartbeat )); then
      printf '       ... %s still running (%ss)\n' "$name" "$elapsed" >&2
      next_heartbeat=$((next_heartbeat + interval))
    fi
  done
  if wait "$pid"; then
    status=0
  else
    status=$?
  fi
  elapsed=$((SECONDS - start))
  build_record_timing "$name" "$elapsed"
  if (( status != 0 )); then
    printf '    !! %s failed after %ss (exit %s)\n' "$name" "$elapsed" "$status" >&2
    if [[ -s "$log_file" ]]; then
      printf '%s\n' '---- failure log tail ----' >&2
      tail -n 80 "$log_file" >&2 || true
      printf '%s\n' '--------------------------' >&2
    fi
    return "$status"
  fi
  printf '    <- %s complete (%ss)\n' "$name" "$elapsed" >&2
}

build_timing_summary() {
  local i total=0
  ((${#BUILD_TIMING_NAMES[@]})) || return 0
  printf '\nTiming summary:\n' >&2
  for ((i=0; i<${#BUILD_TIMING_NAMES[@]}; i++)); do
    printf '  %-36s %6ss\n' "${BUILD_TIMING_NAMES[$i]}" "${BUILD_TIMING_SECONDS[$i]}" >&2
    total=$((total + BUILD_TIMING_SECONDS[$i]))
  done
  printf '  %-36s %6ss\n' 'tracked long-running work' "$total" >&2
}

build_write_archive() {
  local root="$1" dest="$2" mtime="$3"
  tar --sort=name --format=gnu --numeric-owner --owner=0 --group=0 \
    --mtime="$mtime" --clamp-mtime \
    -cf - -C "$(dirname -- "$root")" "$(basename -- "$root")" | gzip -n > "$dest"
}

build_jobs() {
  local jobs="${ERPI_BUILD_JOBS:-}"
  if [[ -z "$jobs" ]]; then
    if command -v nproc >/dev/null 2>&1; then
      jobs="$(nproc)"
    else
      jobs="$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '2')"
    fi
  fi
  [[ "$jobs" =~ ^[1-9][0-9]*$ ]] || {
    echo "ERPI_BUILD_JOBS must be a positive integer; found: $jobs" >&2
    return 2
  }
  printf '%s\n' "$jobs"
}

build_acquire_verified() {
  local url="$1" dest="$2" expected="$3" tmp
  mkdir -p "$(dirname -- "$dest")"
  if [[ -s "$dest" ]]; then
    if build_verify_sha256 "$dest" "$expected" >/dev/null 2>&1; then
      echo "Using verified cached $(basename -- "$dest")"
      return 0
    fi
    echo "Discarding invalid cached $(basename -- "$dest")" >&2
    rm -f -- "$dest"
  fi

  tmp="${dest}.part.$$"
  rm -f -- "$tmp"
  if ! curl --fail --location --proto '=https' --tlsv1.2 \
      --retry 4 --retry-all-errors --connect-timeout 20 \
      -o "$tmp" "$url"; then
    rm -f -- "$tmp"
    echo "Failed to download pinned artifact: $url" >&2
    return 1
  fi
  if ! build_verify_sha256 "$tmp" "$expected"; then
    rm -f -- "$tmp"
    return 1
  fi
  mv -- "$tmp" "$dest"
}

build_docker_image_ref() {
  local image="$1" digest="$2" ref log_file
  ref="${image}@sha256:${digest}"
  if ! docker image inspect "$ref" >/dev/null 2>&1; then
    log_file="${TMPDIR:-/tmp}/erpi-docker-pull-${digest:0:12}.$$.log"
    build_run_logged "Pull pinned Docker image ${image}" "$log_file" docker pull "$ref"
    rm -f -- "$log_file"
  fi
  docker image inspect "$ref" >/dev/null 2>&1 || {
    echo "Pinned Docker image unavailable after pull: $ref" >&2
    return 1
  }
  printf '%s\n' "$ref"
}

# Connected build resolution should not inherit a caller's accidental offline-only
# selection while still preserving normal registry/index, proxy, CA, and auth config.
build_connected_pip() {
  PIP_NO_INDEX=false "$@"
}

build_connected_npm() {
  NPM_CONFIG_OFFLINE=false NPM_CONFIG_PREFER_OFFLINE=false "$@"
}
