#!/usr/bin/env bash
set -euo pipefail
ROOT="${TEST_ROOT:-$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
REAL_GIT="$(command -v git)"
mkdir -p "$TMP/bin"
cp "${GITHUB_SCRIPT_OVERRIDE:-$ROOT/templates/scripts/github.sh}" "$TMP/github.sh"
chmod +x "$TMP/github.sh"

# Real Git for ordinary commands; intercept only the networked push dry-run.
cat > "$TMP/bin/git" <<SHGIT
#!/bin/sh
if [ "\${1:-}" = push ] && [ "\${2:-}" = --dry-run ] && [ "\${3:-}" = --no-verify ]; then
  printf '%s\n' "\$*" >> "$TMP/git-push.log"
  exit 0
fi
exec "$REAL_GIT" "\$@"
SHGIT
chmod +x "$TMP/bin/git"
export PATH="$TMP/bin:$PATH"

# No credential: status says auth is appropriate; auth performs mock OAuth.
cat > "$TMP/bin/gh" <<'EOFGH'
#!/bin/sh
state="${MOCK_GH_STATE:?}"
case "$1 $2" in
  "--version ") echo 'gh version test'; exit 0 ;;
  "auth token") test -f "$state" && exit 0 || exit 1 ;;
  "auth status") test -f "$state" && exit 0 || exit 1 ;;
  "auth login")
    test "${GH_PROMPT_DISABLED:-}" = 1 || { echo 'BUG: GH PROMPTING ENABLED' >&2; exit 98; }
    printf '%s\n' "$*" >> "${MOCK_GH_LOGIN_LOG:?}"
    touch "$state"
    echo 'mock oauth complete'
    exit 0
    ;;
  "api user") test -f "$state" && { echo 'test-user'; exit 0; } ;;
  "repo view") test -f "$state" && { printf 'CrownOpsEng/magnet-photos-env\tADMIN\n'; exit 0; } ;;
esac
if [ "$1 $2" = "auth git-credential" ] && [ "${3:-}" = get ]; then
  cat >/dev/null
  printf 'username=x-access-token\npassword=synthetic-test-credential\n'
  exit 0
fi
exit 1
EOFGH
chmod +x "$TMP/bin/gh"
export MOCK_GH_STATE="$TMP/credential"
export MOCK_GH_LOGIN_LOG="$TMP/login.log"

set +e
"$TMP/github.sh" status >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" -eq 2 ]]
"$TMP/github.sh" auth >"$TMP/auth.out" 2>"$TMP/auth.err"
grep -q 'mock oauth complete' "$TMP/auth.out"
grep -q 'API: ready as test-user' "$TMP/auth.out"
grep -q -- 'auth login --hostname github.com --git-protocol https --web' "$TMP/login.log"
! grep -q 'BUG: GH PROMPTING ENABLED' "$TMP/auth.out" "$TMP/auth.err"

# Stored-but-unusable auth: do not replace it blindly.
cat > "$TMP/bin/gh" <<'EOFGH'
#!/bin/sh
case "$1 $2" in
  "--version ") echo 'gh version test'; exit 0 ;;
  "auth token") exit 0 ;;
  "auth status") exit 1 ;;
  "auth login") echo 'BUG: LOGIN CALLED'; exit 99 ;;
esac
exit 1
EOFGH
chmod +x "$TMP/bin/gh"
set +e
"$TMP/github.sh" auth >"$TMP/stored.out" 2>"$TMP/stored.err"
rc=$?
set -e
[[ "$rc" -eq 1 ]]
! grep -q 'BUG: LOGIN CALLED' "$TMP/stored.out" "$TMP/stored.err"
grep -q 'Not replacing it automatically' "$TMP/stored.err"

# Environment tokens override stored auth; refuse OAuth and never echo the token.
export GH_TOKEN='do-not-leak-this-test-token'
set +e
"$TMP/github.sh" auth >"$TMP/env.out" 2>"$TMP/env.err"
rc=$?
set -e
unset GH_TOKEN
[[ "$rc" -eq 2 ]]
! grep -Fq 'do-not-leak-this-test-token' "$TMP/env.out" "$TMP/env.err"
grep -q 'takes precedence' "$TMP/env.err"

# Current-repo Git readiness uses a repo-local, location-neutral gh helper and
# verifies the push path with --dry-run rather than mutating a remote branch.
cat > "$TMP/bin/gh" <<'EOFGH'
#!/bin/sh
case "$1 $2" in
  "--version ") echo 'gh version test'; exit 0 ;;
  "auth token") exit 0 ;;
  "auth status") exit 0 ;;
  "api user") echo 'test-user'; exit 0 ;;
  "repo view") printf 'CrownOpsEng/magnet-photos-env\tADMIN\n'; exit 0 ;;
esac
if [ "$1 $2" = "auth git-credential" ] && [ "${3:-}" = get ]; then
  cat >/dev/null
  printf 'username=x-access-token\npassword=synthetic-test-credential\n'
  exit 0
fi
exit 1
EOFGH
chmod +x "$TMP/bin/gh"
REPO="$TMP/repo"
mkdir -p "$REPO"
cd "$REPO"
"$REAL_GIT" init -q
"$REAL_GIT" config user.name Test
"$REAL_GIT" config user.email test@example.invalid
printf 'fixture\n' > fixture.txt
"$REAL_GIT" add fixture.txt
"$REAL_GIT" commit -qm fixture
"$REAL_GIT" branch -M main
"$REAL_GIT" remote add origin https://github.com/CrownOpsEng/magnet-photos-env.git
"$TMP/github.sh" git >"$TMP/git-ready.out" 2>"$TMP/git-ready.err"
helpers="$("$REAL_GIT" config --local --get-all credential.https://github.com.helper)"
grep -Fxq '!gh auth git-credential' <<<"$helpers"
grep -q '^push --dry-run --no-verify origin HEAD:refs/heads/main$' "$TMP/git-push.log"
grep -q 'Git push dry-run: ready' "$TMP/git-ready.out"

# The helper intentionally resolves `gh` from PATH, so it survives moving the
# portable environment instead of persisting an absolute bundle path.
HELPER_REPO="$TMP/helper-repo"
mkdir -p "$HELPER_REPO"
cd "$HELPER_REPO"
"$REAL_GIT" init -q
"$REAL_GIT" config --local credential.https://github.com.helper ''
"$REAL_GIT" config --local --add credential.https://github.com.helper '!gh auth git-credential'
printf 'protocol=https\nhost=github.com\n\n' | "$REAL_GIT" credential fill >"$TMP/cred-before"
mkdir -p "$TMP/moved-bin"
mv "$TMP/bin/gh" "$TMP/moved-bin/gh"
OLD_PATH="$PATH"
PATH="$TMP/moved-bin:${OLD_PATH#*:}" printf 'protocol=https\nhost=github.com\n\n' | PATH="$TMP/moved-bin:${OLD_PATH#*:}" "$REAL_GIT" credential fill >"$TMP/cred-after"
cmp "$TMP/cred-before" "$TMP/cred-after"

# Our integration never writes a bundle path to global Git credential config.
global_helpers="$("$REAL_GIT" config --global --get-all credential.https://github.com.helper 2>/dev/null || true)"
! grep -Fq "$ROOT" <<<"$global_helpers"

echo 'GitHub auth and Git transport checks passed.'
