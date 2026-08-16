#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$ROOT"
[[ -f manifest/SHA256SUMS ]] || { echo "manifest/SHA256SUMS is missing" >&2; exit 1; }
sha256sum -c manifest/SHA256SUMS
current_links="$(mktemp)"
trap 'rm -f "$current_links"' EXIT
find . -type l ! -path './state/*' -printf '%p\t%l\n' | LC_ALL=C sort > "$current_links"
cmp -s manifest/SYMLINKS "$current_links" || { echo "Symlink manifest mismatch" >&2; diff -u manifest/SYMLINKS "$current_links" >&2 || true; exit 1; }
broken="$(find . -xtype l -print 2>/dev/null || true)"
if [[ -n "$broken" ]]; then
  echo "Broken symlink(s):" >&2
  printf '%s\n' "$broken" >&2
  exit 1
fi
echo "Static payload verification passed."
