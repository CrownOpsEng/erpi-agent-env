#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/agent-env-build-common.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/cache"
# shellcheck disable=SC1091
source "$ROOT/scripts/build-common.sh"

printf 'verified payload\n' > "$TMP/source"
EXPECTED="$(sha256sum "$TMP/source" | awk '{print $1}')"
cat > "$TMP/bin/curl" <<'CURL'
#!/usr/bin/env bash
set -euo pipefail
out=''
while (($#)); do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[[ -n "$out" ]]
cp "$FAKE_CURL_SOURCE" "$out"
CURL
chmod +x "$TMP/bin/curl"
PATH="$TMP/bin:$PATH" FAKE_CURL_SOURCE="$TMP/source" build_acquire_verified \
  'https://example.invalid/artifact' "$TMP/cache/artifact" "$EXPECTED"
build_verify_sha256 "$TMP/cache/artifact" "$EXPECTED"

# A corrupt cache entry is not sticky: connected acquisition replaces it.
printf 'corrupt\n' > "$TMP/cache/artifact"
PATH="$TMP/bin:$PATH" FAKE_CURL_SOURCE="$TMP/source" build_acquire_verified \
  'https://example.invalid/artifact' "$TMP/cache/artifact" "$EXPECTED" >/dev/null 2>&1
build_verify_sha256 "$TMP/cache/artifact" "$EXPECTED"

# A bad download is rejected before becoming the cache entry.
printf 'wrong\n' > "$TMP/wrong"
rm -f "$TMP/cache/rejected"
if PATH="$TMP/bin:$PATH" FAKE_CURL_SOURCE="$TMP/wrong" build_acquire_verified \
    'https://example.invalid/rejected' "$TMP/cache/rejected" "$EXPECTED" >/dev/null 2>&1; then
  echo 'Bad artifact unexpectedly passed shared acquisition verification.' >&2
  exit 1
fi
[[ ! -e "$TMP/cache/rejected" ]]

PIP_INDEX_URL='https://mirror.example/simple' PIP_NO_INDEX=1 build_connected_pip \
  bash -ceu '[[ "$PIP_NO_INDEX" == false && "$PIP_INDEX_URL" == https://mirror.example/simple ]]'
NPM_CONFIG_REGISTRY='https://registry.example/' NPM_CONFIG_OFFLINE=true NPM_CONFIG_PREFER_OFFLINE=true build_connected_npm \
  bash -ceu '[[ "$NPM_CONFIG_OFFLINE" == false && "$NPM_CONFIG_PREFER_OFFLINE" == false && "$NPM_CONFIG_REGISTRY" == https://registry.example/ ]]'

echo 'Shared build acquisition checks passed.'
