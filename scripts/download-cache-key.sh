#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
python3 - "$ROOT/versions.env" "$ROOT/requirements.lock" <<'PY'
from pathlib import Path
import hashlib,re,sys
excluded={"BUNDLE_VERSION","BUILD_CUTOFF","ARCHIVE_MTIME","TARGET","MIN_KERNEL_VERSION","MIN_GLIBC_VERSION","MIN_GLIBCXX_SYMBOL"}
assign=re.compile(r'^([A-Z][A-Z0-9_]*)="([^"]*)"$')
items=[]
for raw in Path(sys.argv[1]).read_text(encoding="utf-8").splitlines():
    m=assign.fullmatch(raw)
    if m and m.group(1) not in excluded: items.append(m.groups())
h=hashlib.sha256(); h.update(b"magnet-agent-env-download-cache-v1\0")
for name,value in sorted(items):
    h.update(name.encode()); h.update(b"="); h.update(value.encode()); h.update(b"\0")
h.update(b"requirements.lock\0"); h.update(Path(sys.argv[2]).read_bytes())
print(h.hexdigest())
PY
