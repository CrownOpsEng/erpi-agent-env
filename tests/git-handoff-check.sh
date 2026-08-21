#!/usr/bin/env bash
set -euo pipefail
ROOT="${TEST_ROOT:-$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)}"
TOOL="$ROOT/templates/scripts/git-handoff.py"
command -v git >/dev/null 2>&1 || { echo 'git-handoff source test requires host Git.' >&2; exit 1; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/git-handoff-check.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/home" "$TMP/restore-parent"
export HOME="$TMP/home"
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL=/dev/null
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_CONFIG_COUNT || true

SRC="$TMP/source"
git init --quiet "$SRC"
git -C "$SRC" branch -m main
git -C "$SRC" config user.name 'Agent Env Fixture'
git -C "$SRC" config user.email 'fixture@example.invalid'
printf 'base\n' > "$SRC/base.txt"
git -C "$SRC" add base.txt
git -C "$SRC" commit --quiet -m base
BASE_SHA="$(git -C "$SRC" rev-parse HEAD)"
git -C "$SRC" tag fixture-base

git -C "$SRC" switch --quiet -c feature/handoff
printf 'feature\n' > "$SRC/feature.txt"
git -C "$SRC" add feature.txt
git -C "$SRC" commit --quiet -m feature
FEATURE_SHA="$(git -C "$SRC" rev-parse HEAD)"

git -C "$SRC" switch --quiet main
printf 'main\n' > "$SRC/main.txt"
git -C "$SRC" add main.txt
git -C "$SRC" commit --quiet -m main
MAIN_SHA="$(git -C "$SRC" rev-parse HEAD)"
git -C "$SRC" switch --quiet feature/handoff

FULL_BUNDLE="$TMP/repository.bundle"
git -C "$SRC" bundle create "$FULL_BUNDLE" --all
git -C "$SRC" bundle verify "$FULL_BUNDLE" >/dev/null

git -C "$SRC" bundle create "$TMP/incremental.bundle" feature/handoff "^$BASE_SHA"

make_artifact() {
  local out="$1" bundle="$2" sha="$3" branch="$4" repository="$5" mode="${6:-normal}"
  python3 - "$out" "$bundle" "$sha" "$branch" "$repository" "$mode" <<'PY'
import pathlib, stat, sys, warnings, zipfile
out,bundle,sha,branch,repository,mode=sys.argv[1:]
with zipfile.ZipFile(out,'w',compression=zipfile.ZIP_DEFLATED) as z:
    if mode=='symlink':
        info=zipfile.ZipInfo('repository.bundle')
        info.create_system=3
        info.external_attr=(stat.S_IFLNK | 0o777) << 16
        z.writestr(info,'target')
    else:
        z.write(bundle,'repository.bundle')
    z.writestr('SOURCE_SHA',sha+'\n')
    z.writestr('SOURCE_BRANCH',branch+'\n')
    z.writestr('REPOSITORY',repository+'\n')
    if mode=='extra': z.writestr('../escape','nope')
    if mode=='duplicate':
        with warnings.catch_warnings():
            warnings.simplefilter('ignore')
            z.writestr('SOURCE_SHA',sha+'\n')
PY
}

ARTIFACT="$TMP/handoff.zip"
make_artifact "$ARTIFACT" "$FULL_BUNDLE" "$FEATURE_SHA" 'feature/handoff' 'CrownOpsEng/example-repo'

# Poison ordinary host Git configuration. The restore helper must ignore all of it.
cat > "$TMP/poison.gitconfig" <<'EOF'
[credential "https://github.com"]
	helper = !echo SHOULD_NOT_LEAK
[http "https://github.com/"]
	extraheader = AUTHORIZATION: poison
[url "https://attacker.invalid/"]
	insteadOf = https://github.com/
EOF
DEST="$TMP/restore-parent/restored"
GIT_DIR=/not/a/repository GIT_CONFIG_GLOBAL="$TMP/poison.gitconfig" HOME="$TMP/home" \
  python3 "$TOOL" restore "$ARTIFACT" "$DEST" >/dev/null

[[ "$(git -C "$DEST" rev-parse HEAD)" == "$FEATURE_SHA" ]]
[[ "$(git -C "$DEST" rev-parse '@{upstream}')" == "$FEATURE_SHA" ]]
[[ "$(git -C "$DEST" rev-parse refs/remotes/origin/main)" == "$MAIN_SHA" ]]
[[ "$(git -C "$DEST" branch --show-current)" == 'feature/handoff' ]]
[[ "$(git -C "$DEST" remote get-url origin)" == 'https://github.com/CrownOpsEng/example-repo.git' ]]
[[ "$(git -C "$DEST" rev-parse fixture-base)" == "$BASE_SHA" ]]
[[ -f "$DEST/base.txt" && -f "$DEST/feature.txt" && ! -e "$DEST/main.txt" ]]
[[ -z "$(git -C "$DEST" status --porcelain=v1 --untracked-files=all)" ]]
if git -C "$DEST" config --local --get-regexp '^(credential\.|http\..*\.extraheader|include\.|includeif\.)' >/dev/null 2>&1; then
  echo 'Restored repository retained sensitive Git configuration.' >&2
  exit 1
fi

expect_fail_clean() {
  local artifact="$1" dest="$2" label="$3"
  rm -rf "$dest"
  if python3 "$TOOL" restore "$artifact" "$dest" >/dev/null 2>&1; then
    echo "git-handoff negative probe unexpectedly passed: $label" >&2
    exit 1
  fi
  [[ ! -e "$dest" && ! -L "$dest" ]] || { echo "git-handoff negative probe left partial destination: $label" >&2; exit 1; }
}

make_artifact "$TMP/wrong-sha.zip" "$FULL_BUNDLE" '0000000000000000000000000000000000000000' 'feature/handoff' 'CrownOpsEng/example-repo'
expect_fail_clean "$TMP/wrong-sha.zip" "$TMP/restore-parent/wrong-sha" 'branch/SHA mismatch'

make_artifact "$TMP/wrong-branch.zip" "$FULL_BUNDLE" "$FEATURE_SHA" main 'CrownOpsEng/example-repo'
expect_fail_clean "$TMP/wrong-branch.zip" "$TMP/restore-parent/wrong-branch" 'declared branch tip mismatch'

make_artifact "$TMP/bad-repo.zip" "$FULL_BUNDLE" "$FEATURE_SHA" 'feature/handoff' 'https://github.com/CrownOpsEng/example-repo'
expect_fail_clean "$TMP/bad-repo.zip" "$TMP/restore-parent/bad-repo" 'noncanonical repository metadata'

make_artifact "$TMP/incremental.zip" "$TMP/incremental.bundle" "$FEATURE_SHA" 'feature/handoff' 'CrownOpsEng/example-repo'
expect_fail_clean "$TMP/incremental.zip" "$TMP/restore-parent/incremental" 'prerequisite bundle'

make_artifact "$TMP/extra.zip" "$FULL_BUNDLE" "$FEATURE_SHA" 'feature/handoff' 'CrownOpsEng/example-repo' extra
expect_fail_clean "$TMP/extra.zip" "$TMP/restore-parent/extra" 'unexpected/traversal ZIP member'

make_artifact "$TMP/duplicate.zip" "$FULL_BUNDLE" "$FEATURE_SHA" 'feature/handoff' 'CrownOpsEng/example-repo' duplicate
expect_fail_clean "$TMP/duplicate.zip" "$TMP/restore-parent/duplicate" 'duplicate ZIP member'

make_artifact "$TMP/symlink.zip" "$FULL_BUNDLE" "$FEATURE_SHA" 'feature/handoff' 'CrownOpsEng/example-repo' symlink
expect_fail_clean "$TMP/symlink.zip" "$TMP/restore-parent/symlink" 'symlink-like ZIP member'

EXISTING="$TMP/restore-parent/existing"
mkdir "$EXISTING"
printf 'preserve\n' > "$EXISTING/sentinel"
if python3 "$TOOL" restore "$ARTIFACT" "$EXISTING" >/dev/null 2>&1; then
  echo 'git-handoff accepted an existing destination.' >&2
  exit 1
fi
grep -Fx preserve "$EXISTING/sentinel" >/dev/null

echo 'Git handoff checks passed.'
