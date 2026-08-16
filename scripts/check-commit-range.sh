#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
BASE_SHA="${1:-}"
HEAD_SHA="${2:-}"
ZERO_SHA="0000000000000000000000000000000000000000"

[[ "$HEAD_SHA" =~ ^[0-9a-f]{40}$ ]] || {
  echo "Commit-range check requires an exact 40-character head SHA." >&2
  exit 2
}
git cat-file -e "${HEAD_SHA}^{commit}" 2>/dev/null || {
  echo "Head commit is not available locally: $HEAD_SHA" >&2
  exit 2
}

commits=()
if [[ -z "$BASE_SHA" || "$BASE_SHA" == "$ZERO_SHA" ]]; then
  commits=("$HEAD_SHA")
else
  [[ "$BASE_SHA" =~ ^[0-9a-f]{40}$ ]] || {
    echo "Commit-range check requires an exact 40-character base SHA." >&2
    exit 2
  }
  git cat-file -e "${BASE_SHA}^{commit}" 2>/dev/null || {
    echo "Base commit is not available locally: $BASE_SHA" >&2
    exit 2
  }
  mapfile -t commits < <(git rev-list --reverse "${BASE_SHA}..${HEAD_SHA}")
fi

((${#commits[@]} > 0)) || {
  echo "No newly introduced commits to validate."
  exit 0
}

for commit in "${commits[@]}"; do
  subject="$(git show -s --format=%s "$commit")"
  echo "Checking commit ${commit:0:12}: $subject"
  git show -s --format=%B "$commit" | python3 "$ROOT/scripts/check-commit-message.py"
done

echo "Detailed commit history check passed for ${#commits[@]} commit(s)."
