#!/usr/bin/env python3
"""Make uv's install-prefix sysconfig patch relocatable without weakening integrity."""
from pathlib import Path
import sys

SENTINEL = "__ERPI_AGENT_PYTHON_PREFIX__"
SHIM = r'''

# ERPI Agent Environment relocation shim. uv patches python-build-standalone
# sysconfig paths to the install prefix. Replace our location-neutral sentinel
# with the current bundled Python root whenever sysconfig imports this module.
import os as _erpi_os
_erpi_prefix = _erpi_os.path.dirname(_erpi_os.path.dirname(_erpi_os.path.dirname(_erpi_os.path.abspath(__file__))))
build_time_vars = {
    _k: (_v.replace("__ERPI_AGENT_PYTHON_PREFIX__", _erpi_prefix) if isinstance(_v, str) else _v)
    for _k, _v in build_time_vars.items()
}
del _erpi_prefix, _erpi_os
'''


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: normalize-python-sysconfig.py OLD_PREFIX SYSCONFIG_FILE")
    old_prefix = sys.argv[1]
    path = Path(sys.argv[2])
    text = path.read_text(encoding="utf-8")
    if SENTINEL in text:
        raise SystemExit(f"sysconfig data is already normalized: {path}")
    if old_prefix not in text:
        raise SystemExit(f"uv-managed Python install prefix was not found in {path}")
    path.write_text(text.replace(old_prefix, SENTINEL) + SHIM, encoding="utf-8")


if __name__ == "__main__":
    main()
