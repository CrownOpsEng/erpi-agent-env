#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, text: str) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text, encoding="utf-8")


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one anchor, found {count}: {old[:160]!r}")
    write(path, text.replace(old, new, 1))


build_identity = r'''#!/usr/bin/env bash
set -euo pipefail

compute_build_identity() {
  local bundle_version="${1:-}"
  local source_commit="${2:-}"
  local target="${3:-}"

  [[ "$bundle_version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-dev|-rc\.[1-9][0-9]*)?$ ]] || {
    echo "Unsupported BUNDLE_VERSION lifecycle identity: $bundle_version" >&2
    return 2
  }
  [[ "$source_commit" =~ ^[0-9a-f]{40}$ ]] || {
    echo "Source commit must be an exact 40-character lowercase Git SHA." >&2
    return 2
  }

  local artifact_platform
  case "$target" in
    linux-x86_64-gnu) artifact_platform="linux-x64" ;;
    *) echo "Unsupported artifact target for build identity: $target" >&2; return 2 ;;
  esac

  if [[ "$bundle_version" == *-dev ]]; then
    BUILD_ID="${bundle_version}+g${source_commit:0:12}"
  else
    BUILD_ID="$bundle_version"
  fi
  ARTIFACT_STEM="magnet-agent-env-${artifact_platform}-v${BUILD_ID}"
  export BUILD_ID ARTIFACT_STEM
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  [[ $# -eq 3 ]] || {
    echo "Usage: $0 BUNDLE_VERSION SOURCE_COMMIT TARGET" >&2
    exit 2
  }
  compute_build_identity "$1" "$2" "$3"
  printf 'build_id=%s\nartifact_stem=%s\n' "$BUILD_ID" "$ARTIFACT_STEM"
fi
'''
write("scripts/build-identity.sh", build_identity)

version_transition = r'''#!/usr/bin/env python3
"""Validate lifecycle-version transitions independently of commit labels."""

from __future__ import annotations

import argparse
import re

VERSION_RE = re.compile(
    r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
    r"(?:(-dev)|-rc\.([1-9][0-9]*))?$"
)


def parse(version: str) -> tuple[str, str]:
    match = VERSION_RE.fullmatch(version)
    if not match:
        raise SystemExit(f"Invalid lifecycle version: {version}")
    base = ".".join(match.group(i) for i in range(1, 4))
    if match.group(4):
        return "dev", base
    if match.group(5):
        return "rc", base
    return "stable", base


def validate(parent: str, current: str, version_only: bool) -> None:
    parent_kind, parent_base = parse(parent)
    current_kind, current_base = parse(current)

    if current == parent:
        if current_kind != "dev":
            raise SystemExit(
                f"Immutable {current_kind} identity {current} cannot name a second source commit"
            )
        return

    if current_kind == "rc":
        if parent_kind != "dev" or parent_base != current_base:
            raise SystemExit(
                f"Release candidate {current} must be cut from matching {current_base}-dev"
            )
        if not version_only:
            raise SystemExit("Cutting a release candidate must be a version-only source change")
        return

    if current_kind == "stable":
        if parent_kind != "rc" or parent_base != current_base:
            raise SystemExit(
                f"Stable {current} must finalize a matching {current_base}-rc.N candidate"
            )
        if not version_only:
            raise SystemExit("Finalizing a stable release must be a version-only source change")
        return

    if parent_kind == "rc":
        if current_kind != "dev" or current_base != parent_base:
            raise SystemExit(
                f"Rejected candidate {parent} must return to matching {parent_base}-dev before further changes"
            )
        return

    # Development target changes and stable -> next development target require
    # semantic judgment, so they remain policy/review decisions rather than a
    # mechanical guess based on diff size or commit type.


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--parent-version", required=True)
    parser.add_argument("--current-version", required=True)
    parser.add_argument("--version-only", required=True, choices=("true", "false"))
    args = parser.parse_args()
    validate(args.parent_version, args.current_version, args.version_only == "true")
    print("Version transition check passed.")


if __name__ == "__main__":
    main()
'''
write("scripts/check-version-transition.py", version_transition)

build_identity_check = r'''#!/usr/bin/env bash
set -euo pipefail
ROOT="${TEST_ROOT:-$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)}"
TOOL="$ROOT/scripts/build-identity.sh"
SHA="0123456789abcdef0123456789abcdef01234567"

check() {
  local version="$1" expected_id="$2" expected_stem="$3"
  local output
  output="$("$TOOL" "$version" "$SHA" linux-x86_64-gnu)"
  grep -Fx "build_id=$expected_id" <<<"$output" >/dev/null
  grep -Fx "artifact_stem=$expected_stem" <<<"$output" >/dev/null
}

check 0.2.0-dev '0.2.0-dev+g0123456789ab' 'magnet-agent-env-linux-x64-v0.2.0-dev+g0123456789ab'
check 0.2.0-rc.8 '0.2.0-rc.8' 'magnet-agent-env-linux-x64-v0.2.0-rc.8'
check 0.2.0 '0.2.0' 'magnet-agent-env-linux-x64-v0.2.0'

if "$TOOL" 0.2.0-dev deadbeef linux-x86_64-gnu >/dev/null 2>&1; then
  echo 'Build identity accepted a non-exact source SHA.' >&2
  exit 1
fi
if "$TOOL" 0.2.0-rc.0 "$SHA" linux-x86_64-gnu >/dev/null 2>&1; then
  echo 'Build identity accepted an invalid RC identity.' >&2
  exit 1
fi
if "$TOOL" 0.2.0-dev "$SHA" linux-arm64 >/dev/null 2>&1; then
  echo 'Build identity accepted an unsupported artifact target.' >&2
  exit 1
fi

echo 'Build identity checks passed.'
'''
write("tests/build-identity-check.sh", build_identity_check)

version_transition_check = r'''#!/usr/bin/env bash
set -euo pipefail
ROOT="${TEST_ROOT:-$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)}"
TOOL="$ROOT/scripts/check-version-transition.py"

pass_case() {
  python3 "$TOOL" --parent-version "$1" --current-version "$2" --version-only "$3" >/dev/null
}
fail_case() {
  if python3 "$TOOL" --parent-version "$1" --current-version "$2" --version-only "$3" >/dev/null 2>&1; then
    echo "Version transition unexpectedly passed: $1 -> $2 (version_only=$3)" >&2
    exit 1
  fi
}

pass_case 0.2.0-dev 0.2.0-dev false
pass_case 0.2.0-dev 0.3.0-dev false
pass_case 0.2.0-dev 0.2.0-rc.8 true
fail_case 0.2.0-dev 0.2.0-rc.8 false
fail_case 0.2.0-rc.8 0.2.0-rc.8 false
fail_case 0.2.0-rc.8 0.2.0-rc.9 true
pass_case 0.2.0-rc.8 0.2.0-dev false
fail_case 0.2.0-rc.8 0.3.0-dev false
pass_case 0.2.0-rc.8 0.2.0 true
fail_case 0.2.0-rc.8 0.2.0 false
fail_case 0.2.0-dev 0.2.0 true
fail_case 0.2.0 0.2.0 false
pass_case 0.2.0 0.2.1-dev false
pass_case 0.2.0 0.3.0-dev false

echo 'Version transition checks passed.'
'''
write("tests/version-transition-check.sh", version_transition_check)

# Build identity is source-derived, not hand-maintained version state.
replace_once(
    "build.sh",
    "done\n\nneed() { command -v \"$1\" >/dev/null 2>&1 || { echo \"Required build command missing: $1\" >&2; exit 1; }; }\n",
    """done

SOURCE_COMMIT=\"${MAGNET_AGENT_SOURCE_COMMIT:-}\"
if command -v git >/dev/null 2>&1 && git -C \"$SELF_DIR\" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  CHECKOUT_COMMIT=\"$(git -C \"$SELF_DIR\" rev-parse HEAD)\"
  if [[ -n \"$SOURCE_COMMIT\" && \"$SOURCE_COMMIT\" != \"$CHECKOUT_COMMIT\" ]]; then
    echo \"MAGNET_AGENT_SOURCE_COMMIT $SOURCE_COMMIT does not match checked-out source $CHECKOUT_COMMIT.\" >&2
    exit 1
  fi
  SOURCE_COMMIT=\"$CHECKOUT_COMMIT\"
  SOURCE_STATUS=\"$(git -C \"$SELF_DIR\" status --porcelain --untracked-files=all)\"
  if [[ -n \"$SOURCE_STATUS\" ]]; then
    echo \"Distributable builds require a clean committed source tree; commit or remove these changes first:\" >&2
    printf '%s\\n' \"$SOURCE_STATUS\" >&2
    exit 1
  fi
elif [[ -z \"$SOURCE_COMMIT\" ]]; then
  echo \"Cannot determine exact source identity. Build from a clean Git checkout or set MAGNET_AGENT_SOURCE_COMMIT to the exact exported commit SHA.\" >&2
  exit 1
fi
[[ \"$SOURCE_COMMIT\" =~ ^[0-9a-f]{40}$ ]] || {
  echo \"Source identity must be an exact 40-character lowercase Git SHA; found: $SOURCE_COMMIT\" >&2
  exit 1
}
# shellcheck disable=SC1091
source \"$SELF_DIR/scripts/build-identity.sh\"
compute_build_identity \"$BUNDLE_VERSION\" \"$SOURCE_COMMIT\" \"$TARGET\"

need() { command -v \"$1\" >/dev/null 2>&1 || { echo \"Required build command missing: $1\" >&2; exit 1; }; }
""",
)
replace_once(
    "build.sh",
    "Build Magnet Agent Environment ${BUNDLE_VERSION} for ${TARGET}.\nRequires an internet-connected supported Linux x86-64 host (kernel >= ${MIN_KERNEL_VERSION}, glibc >= ${MIN_GLIBC_VERSION}) with a working Docker daemon. No sudo is used.\n",
    "Build Magnet Agent Environment ${BUNDLE_VERSION} for ${TARGET}.\nDevelopment archive identity is derived from the exact committed source; exported source trees must set MAGNET_AGENT_SOURCE_COMMIT=<40-hex-sha>.\nRequires an internet-connected supported Linux x86-64 host (kernel >= ${MIN_KERNEL_VERSION}, glibc >= ${MIN_GLIBC_VERSION}) with a working Docker daemon. No sudo is used.\n",
)
replace_once(
    "build.sh",
    "cp \"$SELF_DIR/templates/RUNTIME-README.md\" \"$BUILD/README.md\"\nsed -i \"s/@BUNDLE_VERSION@/$BUNDLE_VERSION/g\" \"$BUILD/README.md\"\nif grep -Fq '@BUNDLE_VERSION@' \"$BUILD/README.md\"; then\n  echo \"Runtime README version placeholder was not rendered.\" >&2\n  exit 1\nfi\n",
    """cp \"$SELF_DIR/templates/RUNTIME-README.md\" \"$BUILD/README.md\"
sed -i \\
  -e \"s/@BUNDLE_VERSION@/$BUNDLE_VERSION/g\" \\
  -e \"s/@BUILD_ID@/$BUILD_ID/g\" \\
  -e \"s/@SOURCE_COMMIT@/$SOURCE_COMMIT/g\" \\
  \"$BUILD/README.md\"
if grep -Eq '@(BUNDLE_VERSION|BUILD_ID|SOURCE_COMMIT)@' \"$BUILD/README.md\"; then
  echo \"Runtime README build-identity placeholder was not rendered.\" >&2
  exit 1
fi
""",
)
replace_once(
    "build.sh",
    '  "bundle_version": "$BUNDLE_VERSION",\n  "target": "$TARGET",\n',
    '  "bundle_version": "$BUNDLE_VERSION",\n  "build_id": "$BUILD_ID",\n  "source_commit": "$SOURCE_COMMIT",\n  "target": "$TARGET",\n',
)
replace_once(
    "build.sh",
    'ARTIFACT="$OUT_DIR/magnet-agent-env-linux-x64-v${BUNDLE_VERSION}.tar.gz"\n',
    'ARTIFACT="$OUT_DIR/${ARTIFACT_STEM}.tar.gz"\n',
)
replace_once(
    "build.sh",
    'log "Build complete"\necho "$ARTIFACT"\n',
    'log "Build complete"\necho "Build identity: $BUILD_ID"\necho "Source commit: $SOURCE_COMMIT"\necho "$ARTIFACT"\n',
)

# Acceptance metadata validates that the archive name matches the shared build-identity owner.
replace_once(
    "scripts/write-acceptance-metadata.py",
    "import pathlib\nimport re\n",
    "import pathlib\nimport re\nimport subprocess\n",
)
replace_once(
    "scripts/write-acceptance-metadata.py",
    "def main() -> None:\n",
    '''def derive_identity(bundle_version: str, source_sha: str, target: str) -> tuple[str, str]:
    tool = pathlib.Path(__file__).with_name("build-identity.sh")
    try:
        result = subprocess.run(
            [str(tool), bundle_version, source_sha, target],
            check=True,
            capture_output=True,
            text=True,
        )
    except subprocess.CalledProcessError as exc:
        raise SystemExit(exc.stderr.strip() or "Build identity derivation failed") from exc
    fields = dict(line.split("=", 1) for line in result.stdout.splitlines() if "=" in line)
    if set(fields) != {"build_id", "artifact_stem"}:
        raise SystemExit(f"Malformed build identity output: {result.stdout!r}")
    return fields["build_id"], fields["artifact_stem"]


def main() -> None:
''',
)
replace_once(
    "scripts/write-acceptance-metadata.py",
    '    target = quoted_env_value(versions, "TARGET")\n\n    fields = sidecar_path.read_text(encoding="utf-8").strip().split()\n',
    '    target = quoted_env_value(versions, "TARGET")\n    build_id, artifact_stem = derive_identity(bundle_version, args.source_sha, target)\n\n    fields = sidecar_path.read_text(encoding="utf-8").strip().split()\n',
)
replace_once(
    "scripts/write-acceptance-metadata.py",
    '    digest, filename = fields\n\n    artifact_path = sidecar_path.parent / filename\n',
    '    digest, filename = fields\n    expected_filename = f"{artifact_stem}.tar.gz"\n    if filename != expected_filename:\n        raise SystemExit(\n            f"Artifact filename {filename!r} does not match build identity {build_id!r}; expected {expected_filename!r}"\n        )\n\n    artifact_path = sidecar_path.parent / filename\n',
)
replace_once(
    "scripts/write-acceptance-metadata.py",
    '        "bundle_version": bundle_version,\n        "target": target,\n',
    '        "bundle_version": bundle_version,\n        "build_id": build_id,\n        "target": target,\n',
)

# Exact committed-source provenance is part of runtime acceptance itself.
replace_once(
    "templates/scripts/selftest.sh",
    "env=json.loads((root/'manifest/environment.json').read_text(encoding='utf-8'))\npython_meta=env['python_provenance']\n",
    """env=json.loads((root/'manifest/environment.json').read_text(encoding='utf-8'))
bundle_version=env['bundle_version']
build_id=env['build_id']
source_commit=env['source_commit']
assert re.fullmatch(r'[0-9a-f]{40}',source_commit),source_commit
if bundle_version.endswith('-dev'):
    assert build_id==f'{bundle_version}+g{source_commit[:12]}',(bundle_version,build_id,source_commit)
else:
    assert build_id==bundle_version,(bundle_version,build_id)
python_meta=env['python_provenance']
""",
)

# Runtime reference separates compatibility version from exact development build/source identity.
replace_once(
    "templates/RUNTIME-README.md",
    "# Magnet Agent Environment @BUNDLE_VERSION@\n\nPortable Linux x86-64 execution capability for AI-agent work.",
    "# Magnet Agent Environment @BUNDLE_VERSION@\n\nBuild identity: `@BUILD_ID@`  \nSource commit: `@SOURCE_COMMIT@`\n\nPortable Linux x86-64 execution capability for AI-agent work.",
)
replace_once(
    "templates/RUNTIME-README.md",
    "`manifest/environment.json`, `manifest/versions.env`, and the machine-readable `manifest/sources.tsv` record the exact runtime/tool provenance, including the managed python-build-standalone build selected by pinned uv.",
    "`manifest/environment.json` records the compatibility version, derived build identity, exact source commit, and runtime/tool provenance. `manifest/versions.env` and the machine-readable `manifest/sources.tsv` record lifecycle/tool pins and source artifacts, including the managed python-build-standalone build selected by pinned uv.",
)

# Acceptance metadata test now uses the canonical development artifact identity and proves mismatch refusal.
write(
    "tests/acceptance-metadata-check.sh",
    r'''#!/usr/bin/env bash
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
''',
)

# Commit-range validation now enforces immutable candidate/stable identities mechanically.
replace_once(
    "scripts/check-commit-range.sh",
    "for commit in \"${commits[@]}\"; do\n  subject=\"$(git show -s --format=%s \"$commit\")\"\n  echo \"Checking commit ${commit:0:12}: $subject\"\n  git show -s --format=%B \"$commit\" | python3 \"$ROOT/scripts/check-commit-message.py\"\ndone\n",
    r'''version_from_commit() {
  local commit="$1"
  local version
  version="$(git show "$commit:versions.env" | sed -n 's/^BUNDLE_VERSION="\([^"]*\)"$/\1/p')"
  [[ -n "$version" ]] || { echo "Could not resolve BUNDLE_VERSION at $commit" >&2; exit 1; }
  printf '%s\n' "$version"
}

version_change_is_metadata_only() {
  local parent="$1" current="$2"
  local changed=()
  mapfile -t changed < <(git diff --name-only "$parent" "$current" --)
  [[ ${#changed[@]} -eq 1 && "${changed[0]}" == versions.env ]] || return 1
  local parent_normalized current_normalized
  parent_normalized="$(git show "$parent:versions.env" | sed -E 's/^BUNDLE_VERSION="[^"]*"$/BUNDLE_VERSION="<VERSION>"/')"
  current_normalized="$(git show "$current:versions.env" | sed -E 's/^BUNDLE_VERSION="[^"]*"$/BUNDLE_VERSION="<VERSION>"/')"
  [[ "$parent_normalized" == "$current_normalized" ]]
}

for commit in "${commits[@]}"; do
  subject="$(git show -s --format=%s "$commit")"
  echo "Checking commit ${commit:0:12}: $subject"
  git show -s --format=%B "$commit" | python3 "$ROOT/scripts/check-commit-message.py"

  parent="$(git rev-parse "${commit}^1" 2>/dev/null || true)"
  if [[ -n "$parent" ]]; then
    parent_version="$(version_from_commit "$parent")"
    current_version="$(version_from_commit "$commit")"
    version_only=false
    if version_change_is_metadata_only "$parent" "$commit"; then version_only=true; fi
    python3 "$ROOT/scripts/check-version-transition.py" \
      --parent-version "$parent_version" \
      --current-version "$current_version" \
      --version-only "$version_only" >/dev/null
  fi
done
''',
)

# The commit-range fixture carries lifecycle state and the new transition validator.
replace_once(
    "tests/commit-range-check.sh",
    'cp "$ROOT/scripts/check-commit-message.py" "$TMP/check-commit-message.py"\ncp "$ROOT/scripts/check-commit-range.sh" "$TMP/check-commit-range.sh"\n',
    'cp "$ROOT/scripts/check-commit-message.py" "$TMP/check-commit-message.py"\ncp "$ROOT/scripts/check-version-transition.py" "$TMP/check-version-transition.py"\ncp "$ROOT/scripts/check-commit-range.sh" "$TMP/check-commit-range.sh"\n',
)
replace_once(
    "tests/commit-range-check.sh",
    'cp "$TMP/check-commit-message.py" scripts/check-commit-message.py\ncp "$TMP/check-commit-range.sh" scripts/check-commit-range.sh\n\n',
    'cp "$TMP/check-commit-message.py" scripts/check-commit-message.py\ncp "$TMP/check-version-transition.py" scripts/check-version-transition.py\ncp "$TMP/check-commit-range.sh" scripts/check-commit-range.sh\n\nprintf \'BUNDLE_VERSION="0.2.0-dev"\\nTARGET="linux-x86_64-gnu"\\n\' > versions.env\n\n',
)

# Static validation checks semantic routing and identity invariants rather than an arbitrary context byte count.
replace_once(
    "tests/static-check.sh",
    'for file in "$ROOT/build.sh" "$ROOT/tests/"*.sh "$ROOT/templates/scripts/"*.sh "$ROOT/templates/bin/agent-env" "$ROOT/scripts/normalize-python-links.sh"; do\n',
    'for file in "$ROOT/build.sh" "$ROOT/tests/"*.sh "$ROOT/templates/scripts/"*.sh "$ROOT/templates/bin/agent-env" "$ROOT/scripts/normalize-python-links.sh" "$ROOT/scripts/build-identity.sh"; do\n',
)
replace_once(
    "tests/static-check.sh",
    'python3 -m py_compile "$ROOT/scripts/write-acceptance-metadata.py"\n',
    'python3 -m py_compile "$ROOT/scripts/write-acceptance-metadata.py"\npython3 -m py_compile "$ROOT/scripts/check-version-transition.py"\n',
)
replace_once(
    "tests/static-check.sh",
    'for file in requirements.lock payload/AGENTS.md.in templates/RUNTIME-README.md templates/scripts/github.sh templates/scripts/doctor.py templates/scripts/postgres.py templates/scripts/postgrest.py templates/scripts/pgtap.py templates/scripts/node-deps.py templates/scripts/capabilities.py templates/bin/agent-env scripts/uv-isolated-exec.sh scripts/write-acceptance-metadata.py scripts/rebuild-qualified-database-assets.sh vendor/licenses/THIRD-PARTY-LICENSES.md vendor/node-capsules/manifest.json vendor/pg-delta/package.json vendor/pg-delta/package-lock.json vendor/pg-delta/LICENSE vendor/postgrest/LICENSE templates/scripts/pg-delta.mjs tests/node-deps-safety-check.sh; do\n',
    'for file in requirements.lock payload/AGENTS.md.in templates/RUNTIME-README.md templates/scripts/github.sh templates/scripts/doctor.py templates/scripts/postgres.py templates/scripts/postgrest.py templates/scripts/pgtap.py templates/scripts/node-deps.py templates/scripts/capabilities.py templates/bin/agent-env scripts/build-identity.sh scripts/check-version-transition.py scripts/uv-isolated-exec.sh scripts/write-acceptance-metadata.py scripts/rebuild-qualified-database-assets.sh vendor/licenses/THIRD-PARTY-LICENSES.md vendor/node-capsules/manifest.json vendor/pg-delta/package.json vendor/pg-delta/package-lock.json vendor/pg-delta/LICENSE vendor/postgrest/LICENSE templates/scripts/pg-delta.mjs tests/build-identity-check.sh tests/version-transition-check.sh tests/node-deps-safety-check.sh; do\n',
)
replace_once(
    "tests/static-check.sh",
    '# The shipped router is intentionally compact; large operational detail belongs in README/commands.\nrouter_bytes="$(wc -c < "$ROOT/payload/AGENTS.md.in")"\n(( router_bytes <= 3000 )) || { echo "payload/AGENTS.md.in is too large for a routing surface: ${router_bytes} bytes" >&2; exit 1; }\n',
    '# The shipped router is a routing surface; do not enforce an arbitrary byte budget in place of semantic review.\n',
)
replace_once(
    "tests/static-check.sh",
    "grep -F '@BUNDLE_VERSION@' \"$ROOT/templates/RUNTIME-README.md\" >/dev/null\n",
    "grep -F '@BUNDLE_VERSION@' \"$ROOT/templates/RUNTIME-README.md\" >/dev/null\ngrep -F '@BUILD_ID@' \"$ROOT/templates/RUNTIME-README.md\" >/dev/null\ngrep -F '@SOURCE_COMMIT@' \"$ROOT/templates/RUNTIME-README.md\" >/dev/null\n",
)
replace_once(
    "tests/static-check.sh",
    "grep -F '## Development and release version lifecycle' \"$ROOT/CONTRIBUTING.md\" >/dev/null\ngrep -F '## Build identity and candidate boundary' \"$ROOT/VALIDATION.md\" >/dev/null\n",
    """grep -F '## Compatibility and version selection' \"$ROOT/CONTRIBUTING.md\" >/dev/null
grep -F '## Development and release version lifecycle' \"$ROOT/CONTRIBUTING.md\" >/dev/null
grep -F '## Build identity and candidate boundary' \"$ROOT/VALIDATION.md\" >/dev/null
grep -F 'source \"$SELF_DIR/scripts/build-identity.sh\"' \"$ROOT/build.sh\" >/dev/null
grep -F 'MAGNET_AGENT_SOURCE_COMMIT' \"$ROOT/build.sh\" >/dev/null
grep -F 'Distributable builds require a clean committed source tree' \"$ROOT/build.sh\" >/dev/null
grep -F 'ARTIFACT=\"$OUT_DIR/${ARTIFACT_STEM}.tar.gz\"' \"$ROOT/build.sh\" >/dev/null
! grep -F 'magnet-agent-env-linux-x64-v${BUNDLE_VERSION}.tar.gz' \"$ROOT/build.sh\"
grep -F '\"build_id\": \"$BUILD_ID\"' \"$ROOT/build.sh\" >/dev/null
grep -F '\"source_commit\": \"$SOURCE_COMMIT\"' \"$ROOT/build.sh\" >/dev/null
grep -F 'expected_filename = f\"{artifact_stem}.tar.gz\"' \"$ROOT/scripts/write-acceptance-metadata.py\" >/dev/null
grep -F \"build_id==f'{bundle_version}+g{source_commit[:12]}'\" \"$ROOT/templates/scripts/selftest.sh\" >/dev/null
""",
)
replace_once(
    "tests/static-check.sh",
    '"$ROOT/tests/github-auth-check.sh"\n',
    '"$ROOT/tests/build-identity-check.sh"\n"$ROOT/tests/version-transition-check.sh"\n"$ROOT/tests/github-auth-check.sh"\n',
)

# Release routing test keeps release-command detail out of the hot root router.
replace_once(
    "tests/release-workflow-check.sh",
    "grep -F '.github/release-request.json' \"$AGENTS\" >/dev/null\ngrep -F 'connector-only session' \"$AGENTS\" >/dev/null\n",
    """grep -F 'Change, commit, version, and release policy: `CONTRIBUTING.md`.' \"$AGENTS\" >/dev/null
if grep -F '.github/release-request.json' \"$AGENTS\" >/dev/null; then
  echo 'Root AGENTS.md should route release policy, not duplicate release-command procedure.' >&2
  exit 1
fi
""",
)

# Workflows bind the built bytes to the checked-out commit and derive Actions artifact names from acceptance metadata.
replace_once(
    ".github/workflows/accept-runtime.yml",
    "      - name: Build and accept runtime\n        run: ./build.sh\n",
    "      - name: Build and accept runtime\n        env:\n          MAGNET_AGENT_SOURCE_COMMIT: ${{ steps.source.outputs.sha }}\n        run: ./build.sh\n",
)
replace_once(
    ".github/workflows/build-dist.yml",
    "      - name: Compute builder download cache key\n",
    """      - name: Record exact source SHA
        id: source
        shell: bash
        run: echo \"sha=$(git rev-parse HEAD)\" >> \"$GITHUB_OUTPUT\"

      - name: Compute builder download cache key
""",
)
replace_once(
    ".github/workflows/build-dist.yml",
    "      - name: Build and accept distribution\n        run: ./build.sh\n",
    "      - name: Build and accept distribution\n        env:\n          MAGNET_AGENT_SOURCE_COMMIT: ${{ steps.source.outputs.sha }}\n        run: ./build.sh\n",
)
replace_once(
    ".github/workflows/build-dist.yml",
    '''      - name: Write acceptance metadata
        id: metadata
        shell: bash
        run: |
          set -euo pipefail
          source ./versions.env
          echo "name=magnet-agent-env-linux-x64-${BUNDLE_VERSION}" >> "$GITHUB_OUTPUT"
          sidecar="$(printf '%s\n' dist/*.tar.gz.sha256)"
          source_sha="$(git rev-parse HEAD)"
          python3 scripts/write-acceptance-metadata.py \
            --sidecar "$sidecar" \
            --output dist/acceptance.json \
            --source-sha "$source_sha" \
            --repository "$GITHUB_REPOSITORY" \
            --workflow "$GITHUB_WORKFLOW" \
            --run-id "$GITHUB_RUN_ID" \
            --run-attempt "$GITHUB_RUN_ATTEMPT" \
            --event "$GITHUB_EVENT_NAME" \
            --release-tag "$RELEASE_TAG"
          cat "$sidecar"
''',
    '''      - name: Write acceptance metadata
        id: metadata
        shell: bash
        env:
          ACCEPTED_SOURCE_SHA: ${{ steps.source.outputs.sha }}
        run: |
          set -euo pipefail
          sidecar="$(printf '%s\n' dist/*.tar.gz.sha256)"
          python3 scripts/write-acceptance-metadata.py \
            --sidecar "$sidecar" \
            --output dist/acceptance.json \
            --source-sha "$ACCEPTED_SOURCE_SHA" \
            --repository "$GITHUB_REPOSITORY" \
            --workflow "$GITHUB_WORKFLOW" \
            --run-id "$GITHUB_RUN_ID" \
            --run-attempt "$GITHUB_RUN_ATTEMPT" \
            --event "$GITHUB_EVENT_NAME" \
            --release-tag "$RELEASE_TAG"
          archive_name="$(jq -er '.artifact.filename' dist/acceptance.json)"
          echo "name=${archive_name%.tar.gz}" >> "$GITHUB_OUTPUT"
          cat "$sidecar"
''',
)

# Builder documentation: current-state portability, compatibility contract, and unambiguous package identity.
replace_once(
    "README.md",
    "The J2911 portable venv was used as a reference. Its strongest idea—self-locating repair of the venv base-Python `home` after a move—is retained. Its stale absolute console-script failure is not: `uv venv --relocatable` owns standard activation/entrypoint portability, the bundle repairs only the one `pyvenv.cfg` value that cannot remain valid when the bundled interpreter itself moves, and stale build-root residue is a hard failure.\n",
    "Relocation uses self-locating repair of the venv base-Python `home` while `uv venv --relocatable` owns standard activation/entrypoint portability. The bundle repairs only the one `pyvenv.cfg` value that cannot remain valid when the bundled interpreter itself moves, and stale build-root residue is a hard failure.\n",
)
replace_once(
    "README.md",
    "Prerequisites: supported GNU/Linux x86-64, Bash, curl, GNU tar, xz/bzip2, sha256sum, find, sed/awk/grep, a working Docker daemon, and internet access. No sudo is used. Docker is a builder capability only; it is not bundled into the runtime.\n",
    "Prerequisites: supported GNU/Linux x86-64, Bash, curl, GNU tar, xz/bzip2, sha256sum, find, sed/awk/grep, a working Docker daemon, and internet access. A normal Git checkout is used to derive and verify exact source identity; an exported source tree without `.git` must provide `MAGNET_AGENT_SOURCE_COMMIT=<40-hex-sha>`. No sudo is used. Docker is a builder capability only; it is not bundled into the runtime.\n",
)
replace_once(
    "README.md",
    '''The artifact name is derived from `BUNDLE_VERSION` in `versions.env`:

```text
magnet-agent-env-linux-x64-v<version>.tar.gz
magnet-agent-env-linux-x64-v<version>.tar.gz.sha256
```

Release candidates use SemVer prerelease identities such as `0.2.0-rc.1`. A candidate must never use the final stable version or create the stable release tag. Only after the candidate has passed direct artifact verification is `BUNDLE_VERSION` promoted to the stable version, and that exact final source commit must pass acceptance again before publication.
''',
    '''`BUNDLE_VERSION` in `versions.env` is the compatibility/lifecycle version, not a per-build identifier. The builder derives exact development build identity from the committed source SHA and refuses dirty Git worktrees:

```text
development: magnet-agent-env-linux-x64-v0.2.0-dev+g<12-char-source>.tar.gz
candidate:   magnet-agent-env-linux-x64-v0.2.0-rc.8.tar.gz
stable:      magnet-agent-env-linux-x64-v0.2.0.tar.gz
```

The full 40-character source commit and derived build ID are recorded inside `manifest/environment.json` and in generated `acceptance.json`; the SHA-256 sidecar identifies the exact archive bytes. Release-candidate and stable filenames intentionally omit source metadata because those version identities are immutable and executable transition checks prevent a second source commit from retaining the same RC/stable identity.

Release candidates use SemVer prerelease identities such as `0.2.0-rc.1`. A candidate must never use the final stable version or create the stable release tag. Only after the candidate has passed direct artifact verification is `BUNDLE_VERSION` promoted to the stable version, and that exact final source commit must pass acceptance again before publication.
''',
)
replace_once(
    "README.md",
    "PostgreSQL server provenance now terminates at the pinned official source artifact and pinned build image rather than an opaque prebuilt server bundle; the official PostgreSQL copyright notice is retained in the runtime.\n",
    "PostgreSQL server provenance terminates at the pinned official source artifact and pinned build image rather than an opaque prebuilt server bundle; the official PostgreSQL copyright notice is retained in the runtime.\n",
)

compatibility_section = '''## Compatibility and version selection

`BUNDLE_VERSION` is the SemVer compatibility/lifecycle authority for the environment. It is **not** a commit counter and does not identify each development archive by itself. Git owns exact source identity; the builder combines the development lifecycle version with the source commit when it needs a unique distributable build identity.

The supported compatibility surface is the documented environment contract: `agent-env` commands/options and intentionally exported behavior, archive activation and relocation guarantees, documented offline/credential/security boundaries, and the supported runtime-host envelope. Builder source layout, private helper implementation, temporary build paths, test-fixture structure, and undocumented internal runtime paths are not compatibility promises.

Classify material changes by their real contract effect, regardless of Conventional Commit label or diff size:

- **Internal** — no supported behavior changes.
- **Fix** — restores/corrects supported behavior without incompatibility.
- **Additive** — adds a backward-compatible supported capability.
- **Breaking** — makes a supported behavior or interface incompatible.

Before `1.0.0`, a Fix selects a PATCH release; Additive or Breaking work selects the next MINOR release. From `1.0.0` onward, use normal SemVer: Fix → PATCH, Additive → MINOR, Breaking → MAJOR. Internal work does not force a release by itself. The release target is chosen from the cumulative compatibility impact of the work being released; ordinary commits and PRs do not increment SemVer one-by-one.

Conventional Commit syntax and automation may help discover likely impact, but actual supported-contract impact is authoritative. When compatibility, persistence, security, packaging, or operations materially change, make that consequence explicit in the commit/PR record without creating a second version authority.

'''
replace_once("CONTRIBUTING.md", "## Releases\n", compatibility_section + "## Releases\n")
replace_once(
    "CONTRIBUTING.md",
    "`BUNDLE_VERSION` in `versions.env` is the source lifecycle version. Active work uses `x.y.z-dev`; release candidates use SemVer prerelease identities such as `0.2.0-rc.1` and are not published through the stable release workflow. Stable release tags are exactly `v$BUNDLE_VERSION`.\n",
    "`BUNDLE_VERSION` in `versions.env` is the compatibility/lifecycle version authority. Active work uses `x.y.z-dev`; release candidates use SemVer prerelease identities such as `0.2.0-rc.1` and are not published through the stable release workflow. Stable release tags are exactly `v$BUNDLE_VERSION`. Exact development-build identity is derived from Git source identity rather than stored in `versions.env`.\n",
)
replace_once(
    "CONTRIBUTING.md",
    "- **Development:** keep `BUNDLE_VERSION` at `X.Y.Z-dev` while payload, validation, or release work is still changing or any known blocker remains. The exact identity of a development snapshot is the pair `(BUNDLE_VERSION, source commit)` and may be written for humans as `X.Y.Z-dev+g<short-commit-sha>`. The `+g...` form is derived metadata; never hand-maintain it in `versions.env`.\n",
    "- **Development:** keep `BUNDLE_VERSION` at `X.Y.Z-dev` while payload, validation, or release work is still changing or any known blocker remains. The exact source identity is the full Git commit. Distributable development builds derive `BUILD_ID=X.Y.Z-dev+g<12-char-source>` and use that identity in the archive filename; the full source SHA remains in runtime/acceptance provenance. The builder refuses dirty Git worktrees because an uncommitted tree cannot truthfully claim a commit identity. Exported source without `.git` must supply the exact commit through `MAGNET_AGENT_SOURCE_COMMIT`. Never hand-maintain `+g...` metadata in `versions.env`.\n",
)

replace_once(
    "VALIDATION.md",
    "`./tests/static-check.sh` is the fast source gate. It must fail closed on malformed scripts, inconsistent pins/locks, missing required source, unsafe credential handling, router bloat, invalid portability assumptions, mismatched source-controlled qualified native payloads, malformed provenance metadata, incomplete required direct-license material, and unsafe Node-capsule filesystem/ownership behavior.\n",
    "`./tests/static-check.sh` is the fast source gate. It must fail closed on malformed scripts, inconsistent pins/locks, missing required source, unsafe credential handling, router ownership/structure drift, invalid portability assumptions, mismatched source-controlled qualified native payloads, malformed provenance metadata, incomplete required direct-license material, and unsafe Node-capsule filesystem/ownership behavior.\n",
)
replace_once(
    "VALIDATION.md",
    "The source-controlled PostgreSQL client and plpgsql_check payloads remain qualified build inputs. Their pinned hashes are validated by source checks and by `build.sh` before extraction. Their existing promotion baseline is a controlled GLIBC 2.28 build from pinned PostgreSQL 17.10/plpgsql_check sources; qualified maximum GLIBC requirements were 2.25 for the client payload and 2.17 for plpgsql_check. `scripts/rebuild-qualified-database-assets.sh` retains their pinned maintainer reproduction path.\n",
    "The source-controlled PostgreSQL client and plpgsql_check payloads are qualified build inputs. Their pinned hashes are validated by source checks and by `build.sh` before extraction. They are qualified from a controlled GLIBC 2.28 build using pinned PostgreSQL 17.10/plpgsql_check sources; maximum GLIBC requirements are 2.25 for the client payload and 2.17 for plpgsql_check. `scripts/rebuild-qualified-database-assets.sh` provides their pinned maintainer reproduction path.\n",
)
start = read("VALIDATION.md").index("## Build identity and candidate boundary\n")
end = read("VALIDATION.md").index("## Release authority\n")
validation_text = read("VALIDATION.md")
identity_section = '''## Build identity and candidate boundary

`BUNDLE_VERSION` carries compatibility/lifecycle state, not per-commit uniqueness. Source-controlled values are restricted to stable `X.Y.Z`, active-development `X.Y.Z-dev`, or candidate `X.Y.Z-rc.N`. Git owns exact source identity.

A distributable development build derives `BUILD_ID=X.Y.Z-dev+g<12-char-source>` from the exact 40-character source commit and names the archive `magnet-agent-env-linux-x64-v<BUILD_ID>.tar.gz`. Runtime `manifest/environment.json` and generated `acceptance.json` both retain the full source commit plus `build_id`; the archive SHA-256 remains authority for exact bytes. The `+g...` identifier is generated metadata and never belongs in `versions.env`.

The builder refuses a dirty Git worktree because uncommitted bytes cannot truthfully claim the checked-out commit identity. When building an exported source tree without `.git`, the caller must provide `MAGNET_AGENT_SOURCE_COMMIT=<40-hex-sha>` explicitly. When Git is available, any supplied source identity must exactly match `HEAD`.

Release-candidate and stable artifact filenames use only their SemVer identities because those identities are immutable. Commit-range validation mechanically rejects a second source commit retaining the same RC/stable version, requires RC cuts to be version-only transitions from matching `X.Y.Z-dev`, requires stable finalization to be a version-only transition from matching `X.Y.Z-rc.N`, and requires a rejected candidate to return to matching development state before further source changes.

A release candidate is not a debugging label. Before changing `BUNDLE_VERSION` from `X.Y.Z-dev` to `X.Y.Z-rc.N`, all known release blockers must be closed and the strongest relevant inexpensive/targeted checks must already pass. Pull-request validation and candidate acceptance remain different layers: `Validate` is normal source feedback; `Accept runtime` proves an exact committed runtime artifact.

'''
write("VALIDATION.md", validation_text[:start] + identity_section + validation_text[end:])

# The hot builder router already points release/version work at CONTRIBUTING; leave it small.

# The runtime/build workflow checks should assert source-bound naming rather than duplicate formulas.
replace_once(
    "tests/release-workflow-check.sh",
    "grep -F 'gh release edit \"$RELEASE_TAG\" --draft=false' \"$BUILD\" >/dev/null\n",
    "grep -F 'gh release edit \"$RELEASE_TAG\" --draft=false' \"$BUILD\" >/dev/null\ngrep -F 'MAGNET_AGENT_SOURCE_COMMIT: ${{ steps.source.outputs.sha }}' \"$BUILD\" >/dev/null\ngrep -F \"archive_name=\\\"$(jq -er '.artifact.filename' dist/acceptance.json)\\\"\" \"$BUILD\" >/dev/null\n",
)

# Exact builder source placeholders/identity are current runtime provenance, not a second version authority.
replace_once(
    "tests/static-check.sh",
    "rm -rf \"$ROOT/templates/scripts/__pycache__\" \"$ROOT/scripts/__pycache__\"\n",
    "rm -rf \"$ROOT/templates/scripts/__pycache__\" \"$ROOT/scripts/__pycache__\"\n",
)

# Remove temporary qualification machinery before the permanent tree is validated/committed.
for rel in (".github/version-identity-promote.py", ".github/workflows/version-identity-qualify.yml"):
    path = ROOT / rel
    if path.exists():
        path.unlink()

print("Version/build identity and context-policy transformation complete.")
