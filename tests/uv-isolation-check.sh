#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
cat > "$T/probe.sh" <<'PROBE'
#!/bin/sh
set -eu
[ "${UV_NO_CONFIG:-}" = 1 ]
[ "${UV_NO_SYSTEM_CONFIG:-}" = 1 ]
[ "${UV_ISOLATED:-}" = 1 ]
[ -z "${UV_CONFIG_FILE+x}" ]
[ -z "${UV_PYTHON_DOWNLOADS_JSON_URL+x}" ]
[ -z "${UV_PYTHON_INSTALL_MIRROR+x}" ]
[ -z "${UV_ASTRAL_MIRROR_URL+x}" ]
[ -z "${UV_PYTHON_CPYTHON_BUILD+x}" ]
[ -z "${UV_LIBC+x}" ]
[ -z "${UV_INSECURE_HOST+x}" ]
[ "${HTTPS_PROXY:-}" = "http://proxy.example:8443" ]
[ "${SSL_CERT_FILE:-}" = "/example/ca.pem" ]
[ "${UV_SYSTEM_CERTS:-}" = "true" ]
PROBE
chmod 0755 "$T/probe.sh"
env \
  UV_CONFIG_FILE=/tmp/host-uv.toml \
  UV_PYTHON_DOWNLOADS_JSON_URL=https://example.invalid/python.json \
  UV_PYTHON_INSTALL_MIRROR=https://example.invalid/python \
  UV_ASTRAL_MIRROR_URL=https://example.invalid/astral \
  UV_PYTHON_CPYTHON_BUILD=19000101 \
  UV_LIBC=musl \
  UV_INSECURE_HOST=example.invalid \
  HTTPS_PROXY=http://proxy.example:8443 \
  SSL_CERT_FILE=/example/ca.pem \
  UV_SYSTEM_CERTS=true \
  "$ROOT/scripts/uv-isolated-exec.sh" "$T/probe.sh"
echo "uv build-isolation check passed."
