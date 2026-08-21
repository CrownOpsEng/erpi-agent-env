#!/usr/bin/env bash
set -euo pipefail
ROOT="${TEST_ROOT:-$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cp "$ROOT/versions.env" "$TMP/versions.env"
source_sha=0123456789abcdef0123456789abcdef01234567
artifact='magnet-agent-env-linux-x64-v0.2.0-dev+g0123456789ab.tar.gz'
printf 'payload\n' > "$TMP/$artifact"
digest="$(sha256sum "$TMP/$artifact" | awk '{print $1}')"
printf '%s  %s\n' "$digest" "$artifact" > "$TMP/test.sha256"

python3 "$ROOT/scripts/write-acceptance-metadata.py" \
  --versions "$TMP/versions.env" \
  --sidecar "$TMP/test.sha256" \
  --output "$TMP/acceptance.json" \
  --source-sha "$source_sha" \
  --repository CrownOpsEng/magnet-photos-env \
  --workflow 'Accept runtime' \
  --run-id 123 \
  --run-attempt 2 \
  --event push

python3 - <<'PY' "$TMP/acceptance.json" "$digest" "$artifact" "$source_sha"
import json, pathlib, re, sys
record = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
assert record['schema_version'] == 1
assert record['status'] == 'accepted'
assert record['bundle_version'] == '0.2.0-dev'
assert record['build_id'] == '0.2.0-dev+g0123456789ab'
assert record['target'] == 'linux-x86_64-gnu'
assert record['source_commit'] == sys.argv[4]
assert record['repository'] == 'CrownOpsEng/magnet-photos-env'
assert record['workflow'] == {'name': 'Accept runtime', 'run_id': 123, 'run_attempt': 2, 'event': 'push'}
assert record['artifact']['filename'] == sys.argv[3]
assert record['artifact']['sha256'] == sys.argv[2]
assert record['artifact']['size_bytes'] > 0
assert record['release_tag'] is None
PY

printf '%s  %s\n' "$digest" wrong-name.tar.gz > "$TMP/wrong.sha256"
cp "$TMP/$artifact" "$TMP/wrong-name.tar.gz"
if python3 "$ROOT/scripts/write-acceptance-metadata.py" \
  --versions "$TMP/versions.env" \
  --sidecar "$TMP/wrong.sha256" \
  --output "$TMP/wrong.json" \
  --source-sha "$source_sha" \
  --repository CrownOpsEng/magnet-photos-env \
  --workflow 'Accept runtime' \
  --run-id 124 \
  --run-attempt 1 \
  --event push >/dev/null 2>&1; then
  echo 'Acceptance metadata accepted an artifact name that did not match build identity.' >&2
  exit 1
fi

echo 'Acceptance metadata check passed.'
