#!/usr/bin/env bash
set -euo pipefail
ROOT="${TEST_ROOT:-$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cp "$ROOT/versions.env" "$TMP/versions.env"
printf 'payload\n' > "$TMP/magnet-agent-env-linux-x64-test.tar.gz"
digest="$(sha256sum "$TMP/magnet-agent-env-linux-x64-test.tar.gz" | awk '{print $1}')"
printf '%s  %s\n' "$digest" magnet-agent-env-linux-x64-test.tar.gz > "$TMP/test.sha256"

python3 "$ROOT/scripts/write-acceptance-metadata.py" \
  --versions "$TMP/versions.env" \
  --sidecar "$TMP/test.sha256" \
  --output "$TMP/acceptance.json" \
  --source-sha 0123456789abcdef0123456789abcdef01234567 \
  --repository CrownOpsEng/magnet-photos-env \
  --workflow 'Accept runtime' \
  --run-id 123 \
  --run-attempt 2 \
  --event push

python3 - <<'PY' "$TMP/acceptance.json" "$digest"
import json, pathlib, re, sys
record = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
assert record['schema_version'] == 1
assert record['status'] == 'accepted'
assert re.fullmatch(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-[0-9A-Za-z.-]+)?', record['bundle_version'])
assert record['target'] == 'linux-x86_64-gnu'
assert record['source_commit'] == '0123456789abcdef0123456789abcdef01234567'
assert record['repository'] == 'CrownOpsEng/magnet-photos-env'
assert record['workflow'] == {'name': 'Accept runtime', 'run_id': 123, 'run_attempt': 2, 'event': 'push'}
assert record['artifact']['filename'] == 'magnet-agent-env-linux-x64-test.tar.gz'
assert record['artifact']['sha256'] == sys.argv[2]
assert record['artifact']['size_bytes'] > 0
assert record['release_tag'] is None
PY

echo 'Acceptance metadata check passed.'
