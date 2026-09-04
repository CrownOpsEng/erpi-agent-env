#!/usr/bin/env bash
# Shared connected-builder primitives. This file is sourced; callers own set -euo pipefail.

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
  local image="$1" digest="$2" ref
  ref="${image}@sha256:${digest}"
  if ! docker image inspect "$ref" >/dev/null 2>&1; then
    docker pull "$ref" >/dev/null
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
