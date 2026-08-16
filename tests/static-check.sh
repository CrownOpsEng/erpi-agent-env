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
for file in templates/AGENTS.md templates/RUNTIME-README.md templates/scripts/github.sh templates/scripts/doctor.py templates/bin/agent-env; do
  [[ -s "$ROOT/$file" ]] || { echo "Required runtime source missing: $file" >&2; exit 1; }
done
# The router is intentionally compact; large operational detail belongs in README/commands.
router_bytes="$(wc -c < "$ROOT/templates/AGENTS.md")"
(( router_bytes <= 3000 )) || { echo "templates/AGENTS.md is too large for a routing surface: ${router_bytes} bytes" >&2; exit 1; }
# Authentication must remain host/session state, not redirected into the portable payload.
if grep -R -nE 'export[[:space:]]+GH_CONFIG_DIR=|GH_CONFIG_DIR=' "$ROOT/templates"; then
  echo "Do not redirect GitHub credential storage into the portable bundle." >&2
  exit 1
fi
# Ad-hoc package/runtime installation belongs in mutable state rather than verified payload directories.
grep -F 'UV_PYTHON_INSTALL_DIR="$MAGNET_AGENT_ENV/state/uv-python"' "$ROOT/templates/activate" >/dev/null
grep -F 'NPM_CONFIG_PREFIX="$MAGNET_AGENT_ENV/state/npm-global"' "$ROOT/templates/activate" >/dev/null
# Mutable state is outside immutable payload verification/topology.
grep -F "! -path './state/*'" "$ROOT/templates/scripts/verify.sh" >/dev/null
grep -F '! -path "$ROOT/state/*"' "$ROOT/templates/scripts/selftest.sh" >/dev/null
# Host preflight probes must not use early-closing pipelines under `set -o pipefail`.
if grep -nE '(ldd|tar) --version[^\n]*\|[[:space:]]*head' "$ROOT/build.sh"; then
  echo "Host-version probes must capture output instead of piping through head under pipefail." >&2
  exit 1
fi
grep -F 'getconf GNU_LIBC_VERSION' "$ROOT/build.sh" >/dev/null
"$ROOT/tests/github-auth-check.sh"
echo "Builder static checks passed."
