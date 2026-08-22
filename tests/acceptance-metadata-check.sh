#!/usr/bin/env bash
set -euo pipefail
ROOT="${TEST_ROOT:-$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cp "$ROOT/versions.env" "$TMP/versions.env"
source_sha=0123456789abcdef0123456789abcdef01234567
base_tag=v0.1.1
distance=40
description=v0.1.1-40-g0123456789ab
artifact="magnet-agent-env-linux-x64-${description}.tar.gz"
printf 'payload\n' > "$TMP/$artifact"
digest="$(sha256sum "$TMP/$artifact" | awk '{print $1}')"
printf '%s  %s\n' "$digest" "$artifact" > "$TMP/test.sha256"

python3 "$ROOT/scripts/write-acceptance-metadata.py" \
  --versions "$TMP/versions.env" \
  --sidecar "$TMP/test.sha256" \
  --output "$TMP/acceptance.json" \
  --source-sha "$source_sha" \
  --source-base-tag "$base_tag" \
  --source-distance "$distance" \
  --source-description "$description" \
  --repository CrownOpsEng/magnet-photos-env \
  --workflow 'Accept runtime' \
  --run-id 123 \
  --run-attempt 2 \
  --event push

python3 - <<'PY' "$TMP/acceptance.json" "$digest" "$artifact" "$source_sha"
import json, pathlib, sys
record = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
assert record['schema_version'] == 2
assert record['status'] == 'accepted'
assert record['product_version'] == '0.1.1'
assert record['target'] == 'linux-x86_64-gnu'
assert record['source'] == {
    'commit': sys.argv[4],
    'description': 'v0.1.1-40-g0123456789ab',
    'base_tag': 'v0.1.1',
    'distance': 40,
}
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
  --source-base-tag "$base_tag" \
  --source-distance "$distance" \
  --source-description "$description" \
  --repository CrownOpsEng/magnet-photos-env \
  --workflow 'Accept runtime' \
  --run-id 124 \
  --run-attempt 1 \
  --event push >/dev/null 2>&1; then
  echo 'Acceptance metadata accepted an artifact name that did not match source identity.' >&2
  exit 1
fi

# Exact release/prerelease acceptance must be built from the matching tag.
cat > "$TMP/release.env" <<'ENV'
PRODUCT_VERSION="0.2.0-rc.1"
TARGET="linux-x86_64-gnu"
ENV
release_artifact='magnet-agent-env-linux-x64-v0.2.0-rc.1.tar.gz'
printf 'release\n' > "$TMP/$release_artifact"
release_digest="$(sha256sum "$TMP/$release_artifact" | awk '{print $1}')"
printf '%s  %s\n' "$release_digest" "$release_artifact" > "$TMP/release.sha256"
python3 "$ROOT/scripts/write-acceptance-metadata.py" \
  --versions "$TMP/release.env" \
  --sidecar "$TMP/release.sha256" \
  --output "$TMP/release.json" \
  --source-sha "$source_sha" \
  --source-base-tag v0.2.0-rc.1 \
  --source-distance 0 \
  --source-description v0.2.0-rc.1 \
  --repository CrownOpsEng/magnet-photos-env \
  --workflow 'Build distribution' \
  --run-id 125 \
  --run-attempt 1 \
  --event workflow_dispatch \
  --release-tag v0.2.0-rc.1

echo 'Acceptance metadata check passed.'
