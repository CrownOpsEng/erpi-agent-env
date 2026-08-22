#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

new_repo() {
  local dir="$1"
  mkdir -p "$dir/scripts" "$dir/.github"
  git -C "$dir" init -q
  git -C "$dir" config user.name 'Commit Policy Test'
  git -C "$dir" config user.email 'commit-policy@example.invalid'
  cp "$ROOT/scripts/check-commit-message.py" "$dir/scripts/check-commit-message.py"
  cp "$ROOT/scripts/check-version-transition.py" "$dir/scripts/check-version-transition.py"
  cp "$ROOT/scripts/check-commit-range.sh" "$dir/scripts/check-commit-range.sh"
  chmod +x "$dir/scripts/check-commit-range.sh"
}

good_message() {
  local subject="$1" detail="$2"
  cat <<EOF_MSG
$subject

Why:
$detail exists to preserve enough reasoning for future audit and resumption without loading unrelated repository history.

What:
The fixture records a substantive final-state implementation description so policy checks semantic content rather than headings alone.

Verified:
The temporary Git repository is exercised by the production commit-range checker and this regression asserts the expected result.
EOF_MSG
}

write_request() {
  local version="$1"
  printf '{\n  "version": "%s"\n}\n' "$version" > .github/release-request.json
}

# Normal release -> development -> RC cut -> RC-attached development -> next RC.
REPO="$TMP/lifecycle"
new_repo "$REPO"
cd "$REPO"
printf 'PRODUCT_VERSION="0.1.1"\nTARGET="linux-x86_64-gnu"\n' > versions.env
write_request 0.1.1
echo base > file.txt
git add .
good_message 'chore(repo): create released fixture' 'The initial released checkpoint' > "$TMP/message"
git commit -q -F "$TMP/message"
git tag v0.1.1

base="$(git rev-parse HEAD)"
echo dev >> file.txt
git add file.txt
good_message 'feat(runtime): add development capability' 'A normal development source commit' > "$TMP/message"
git commit -q -F "$TMP/message"
dev_head="$(git rev-parse HEAD)"
./scripts/check-commit-range.sh "$base" "$dev_head" >/dev/null

printf 'PRODUCT_VERSION="0.2.0-rc.1"\nTARGET="linux-x86_64-gnu"\n' > versions.env
write_request 0.2.0-rc.1
git add versions.env .github/release-request.json
good_message 'chore(release): cut 0.2.0-rc.1' 'The first release candidate metadata checkpoint' > "$TMP/message"
git commit -q -F "$TMP/message"
rc1_cut="$(git rev-parse HEAD)"
./scripts/check-commit-range.sh "$dev_head" "$rc1_cut" >/dev/null

# Source may not continue under the new product version until the matching tag exists.
echo illegal >> file.txt
git add file.txt
good_message 'fix(runtime): change source before candidate tag' 'An illegal pre-tag descendant' > "$TMP/message"
git commit -q -F "$TMP/message"
illegal="$(git rev-parse HEAD)"
if ./scripts/check-commit-range.sh "$rc1_cut" "$illegal" >/dev/null 2>&1; then
  echo 'Commit-range checker allowed source continuation before the RC tag existed.' >&2
  exit 1
fi
git reset -q --hard "$rc1_cut"

git tag v0.2.0-rc.1
echo fix1 >> file.txt
git add file.txt
good_message 'fix(runtime): correct candidate defect' 'A first development correction after the tagged candidate' > "$TMP/message"
git commit -q -F "$TMP/message"
echo fix2 >> file.txt
git add file.txt
good_message 'fix(runtime): complete candidate correction' 'A second development correction after the tagged candidate' > "$TMP/message"
git commit -q -F "$TMP/message"
rc1_dev2="$(git rev-parse HEAD)"
./scripts/check-commit-range.sh "$rc1_cut" "$rc1_dev2" >/dev/null
base_tag="$(git describe --tags --match 'v[0-9]*' --abbrev=0 --first-parent HEAD)"
distance="$(git rev-list --count --first-parent "${base_tag}..HEAD")"
[[ "$base_tag" == v0.2.0-rc.1 && "$distance" == 2 ]] || {
  echo "RC descendant did not remain attached to v0.2.0-rc.1: $base_tag distance $distance" >&2
  exit 1
}

printf 'PRODUCT_VERSION="0.2.0-rc.2"\nTARGET="linux-x86_64-gnu"\n' > versions.env
write_request 0.2.0-rc.2
git add versions.env .github/release-request.json
good_message 'chore(release): cut 0.2.0-rc.2' 'The next immutable candidate metadata checkpoint' > "$TMP/message"
git commit -q -F "$TMP/message"
rc2_cut="$(git rev-parse HEAD)"
./scripts/check-commit-range.sh "$rc1_dev2" "$rc2_cut" >/dev/null

# Version changes mixed with runtime/source changes are rejected.
git tag v0.2.0-rc.2
printf 'PRODUCT_VERSION="0.2.0"\nTARGET="linux-x86_64-gnu"\n' > versions.env
write_request 0.2.0
echo mixed >> file.txt
git add versions.env .github/release-request.json file.txt
good_message 'chore(release): mix finalization with runtime source' 'An invalid mixed finalization checkpoint' > "$TMP/message"
git commit -q -F "$TMP/message"
mixed="$(git rev-parse HEAD)"
if ./scripts/check-commit-range.sh "$rc2_cut" "$mixed" >/dev/null 2>&1; then
  echo 'Commit-range checker allowed PRODUCT_VERSION to change with runtime source.' >&2
  exit 1
fi

# One-time migration from legacy BUNDLE_VERSION must attach to the nearest real tag.
LEGACY="$TMP/legacy"
new_repo "$LEGACY"
cd "$LEGACY"
printf 'BUNDLE_VERSION="0.1.1"\nTARGET="linux-x86_64-gnu"\n' > versions.env
printf '{\n  "version": "0.1.1",\n  "target_sha": "0123456789abcdef0123456789abcdef01234567"\n}\n' > .github/release-request.json
echo released > file.txt
git add .
good_message 'chore(repo): create legacy release fixture' 'The legacy released checkpoint' > "$TMP/message"
git commit -q -F "$TMP/message"
git tag v0.1.1
printf 'BUNDLE_VERSION="0.2.0-dev"\nTARGET="linux-x86_64-gnu"\n' > versions.env
echo legacy-dev >> file.txt
git add versions.env file.txt
good_message 'feat(runtime): create legacy development source' 'The legacy pseudo-version development checkpoint' > "$TMP/message"
git commit -q -F "$TMP/message"
legacy_parent="$(git rev-parse HEAD)"
printf 'PRODUCT_VERSION="0.1.1"\nTARGET="linux-x86_64-gnu"\n' > versions.env
write_request 0.1.1
echo migration > policy.txt
git add versions.env .github/release-request.json policy.txt
good_message 'refactor(release)!: adopt tagged source ancestry' 'The one-time authority migration checkpoint' > "$TMP/message"
git commit -q -F "$TMP/message"
legacy_migration="$(git rev-parse HEAD)"
./scripts/check-commit-range.sh "$legacy_parent" "$legacy_migration" >/dev/null

echo 'Detailed commit-range policy checks passed.'
