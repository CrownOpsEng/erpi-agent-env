#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
for file in "$ROOT/build.sh" "$ROOT/tests/"*.sh "$ROOT/templates/scripts/"*.sh "$ROOT/templates/bin/agent-env"; do
  bash -n "$file"
done
for file in "$ROOT/templates/bin/python-wrapper" "$ROOT/templates/bin/node-wrapper" "$ROOT/templates/bin/npm-wrapper" "$ROOT/templates/bin/npx-wrapper"; do
  sh -n "$file"
done
python3 -m py_compile "$ROOT/templates/scripts/doctor.py"
python3 - <<'PY' "$ROOT/versions.env"
import re, sys
text=open(sys.argv[1], encoding='utf-8').read()
for name, value in re.findall(r'^(\w+_SHA256)="([0-9a-f]+)"$', text, flags=re.M):
    assert len(value) == 64, (name, value)
print('hash-shapes-ok')
PY
rm -rf "$ROOT/templates/scripts/__pycache__"
echo "Builder static checks passed."
