#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
cp "$ROOT/templates/scripts/github.sh" "$TMP/github.sh"
chmod +x "$TMP/github.sh"
cat > "$TMP/bin/git" <<'SH'
#!/bin/sh
exit 1
SH
chmod +x "$TMP/bin/git"
export PATH="$TMP/bin:$PATH"

# No credential: status says auth is appropriate; auth performs the mock OAuth flow.
cat > "$TMP/bin/gh" <<'SH'
#!/bin/sh
state="${MOCK_GH_STATE:?}"
case "$1 $2" in
  "--version ") echo 'gh version test'; exit 0 ;;
  "auth token") test -f "$state" && exit 0 || exit 1 ;;
  "auth status") test -f "$state" && exit 0 || exit 1 ;;
  "auth login") touch "$state"; echo 'mock oauth complete'; exit 0 ;;
  "api user") test -f "$state" && { echo 'test-user'; exit 0; } ;;
esac
exit 1
SH
chmod +x "$TMP/bin/gh"
export MOCK_GH_STATE="$TMP/credential"
set +e
"$TMP/github.sh" status >/dev/null 2>&1
rc=$?
set -e
[[ "$rc" -eq 2 ]]
"$TMP/github.sh" auth >"$TMP/auth.out" 2>"$TMP/auth.err"
grep -q 'mock oauth complete' "$TMP/auth.out"
grep -q 'API: ready as test-user' "$TMP/auth.out"

# Stored-but-unusable auth: do not replace it blindly.
cat > "$TMP/bin/gh" <<'SH'
#!/bin/sh
case "$1 $2" in
  "--version ") echo 'gh version test'; exit 0 ;;
  "auth token") exit 0 ;;
  "auth status") exit 1 ;;
  "auth login") echo 'BUG: LOGIN CALLED'; exit 99 ;;
esac
exit 1
SH
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

echo 'GitHub auth state-machine checks passed.'
