#!/bin/sh
set -eu

# Builder/recovery uv operations must not inherit project/user configuration or
# artifact-selection overrides. Network transport settings (proxy, CA/system
# certificates) are intentionally preserved.
unset UV_CONFIG_FILE
unset UV_PYTHON_DOWNLOADS_JSON_URL
unset UV_PYTHON_INSTALL_MIRROR
unset UV_ASTRAL_MIRROR_URL
unset UV_PYTHON_CPYTHON_BUILD
unset UV_PYTHON
unset UV_SYSTEM_PYTHON
unset UV_PYTHON_PREFERENCE
unset UV_MANAGED_PYTHON
unset UV_NO_MANAGED_PYTHON
unset UV_PYTHON_DOWNLOADS
unset UV_PYTHON_INSTALL_DIR
unset UV_LIBC
unset UV_OFFLINE
unset UV_INSECURE_HOST
unset UV_INSECURE_NO_ZIP_VALIDATION

export UV_NO_CONFIG=1
export UV_NO_SYSTEM_CONFIG=1
export UV_ISOLATED=1

exec "$@"
