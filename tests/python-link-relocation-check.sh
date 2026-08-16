#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/python/cpython-3.13.14-linux-x86_64-gnu/bin"
ln -s "$T/python/cpython-3.13.14-linux-x86_64-gnu" "$T/python/cpython-3.13-linux-x86_64-gnu"
"$ROOT/scripts/normalize-python-links.sh" "$T/python"
[[ "$(readlink "$T/python/cpython-3.13-linux-x86_64-gnu")" == 'cpython-3.13.14-linux-x86_64-gnu' ]]
mkdir -p "$T/external"
ln -s "$T/external" "$T/python/external-link"
if "$ROOT/scripts/normalize-python-links.sh" "$T/python" >/dev/null 2>&1; then
  echo "normalize-python-links.sh accepted an external absolute target" >&2
  exit 1
fi
echo "Managed-Python link relocation check passed."
