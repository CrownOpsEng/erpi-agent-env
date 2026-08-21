#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cp "$ROOT/scripts/check-commit-message.py" "$TMP/check-commit-message.py"
cp "$ROOT/scripts/check-version-transition.py" "$TMP/check-version-transition.py"
cp "$ROOT/scripts/check-commit-range.sh" "$TMP/check-commit-range.sh"
chmod +x "$TMP/check-commit-range.sh"
mkdir "$TMP/repo"
cd "$TMP/repo"
git init -q
git config user.name 'Commit Policy Test'
git config user.email 'commit-policy@example.invalid'
mkdir -p scripts
cp "$TMP/check-commit-message.py" scripts/check-commit-message.py
cp "$TMP/check-version-transition.py" scripts/check-version-transition.py
cp "$TMP/check-commit-range.sh" scripts/check-commit-range.sh

printf 'BUNDLE_VERSION="0.2.0-dev"\nTARGET="linux-x86_64-gnu"\n' > versions.env

good_message() {
  local subject="$1" detail="$2"
  cat <<EOF
$subject

Why:
$detail exists to preserve enough reasoning for future audit and learning from repository history.

What:
The fixture records a substantive implementation description so the policy checks real content rather than headings alone.

Validation:
The temporary repository is checked by the production commit-range script and the surrounding test asserts the expected result.
EOF
}

echo one > file.txt
git add .
good_message 'chore(repo): create commit policy fixture' 'The initial commit' > "$TMP/message"
git commit -q -F "$TMP/message"
base="$(git rev-parse HEAD)"

echo two >> file.txt
git add file.txt
good_message 'test(repo): add compliant history commit' 'A compliant second commit' > "$TMP/message"
git commit -q -F "$TMP/message"
good_head="$(git rev-parse HEAD)"
./scripts/check-commit-range.sh "$base" "$good_head" >/dev/null

echo three >> file.txt
git add file.txt
git commit -q -m 'fix(repo): terse invalid history commit'
bad_head="$(git rev-parse HEAD)"
if ./scripts/check-commit-range.sh "$base" "$bad_head" >/dev/null 2>&1; then
  echo 'Commit-range checker accepted history containing a noncompliant commit.' >&2
  exit 1
fi

echo "Detailed commit-range policy checks passed."
