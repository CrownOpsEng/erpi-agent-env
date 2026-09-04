#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
OLD="$T/Old Root With Spaces/python"
NEW="$T/New Root – moved/python"
SC_REL='lib/python3.13/_sysconfigdata__linux_x86_64-linux-gnu.py'
mkdir -p "$OLD/$(dirname -- "$SC_REL")"
cat > "$OLD/$SC_REL" <<DATA
build_time_vars = {'BINDIR': '$OLD/bin', 'LIBDIR': '$OLD/lib', 'OTHER': 'cc'}
DATA
python3 "$ROOT/scripts/normalize-python-sysconfig.py" "$OLD" "$OLD/$SC_REL"
! grep -F "$OLD" "$OLD/$SC_REL" >/dev/null
mkdir -p "$(dirname -- "$NEW")"
mv "$OLD" "$NEW"
python3 - "$NEW/$SC_REL" "$NEW" <<'PY'
import importlib.util
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
expected = pathlib.Path(sys.argv[2])
spec = importlib.util.spec_from_file_location("erpi_sysconfig_test", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
assert pathlib.Path(module.build_time_vars["BINDIR"]) == expected / "bin"
assert pathlib.Path(module.build_time_vars["LIBDIR"]) == expected / "lib"
assert "__ERPI_AGENT_PYTHON_PREFIX__" not in repr(module.build_time_vars)
PY
echo "Python sysconfig relocation check passed."
