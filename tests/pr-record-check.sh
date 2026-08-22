#!/usr/bin/env bash
set -euo pipefail
ROOT="${TEST_ROOT:-$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)}"
TOOL="$ROOT/scripts/check-pr-record.py"

valid='## Why

The source and compatibility identities need one semantic owner each so review history and release artifacts remain deterministic.

## What

Replace pseudo-development versions with tagged Git ancestry and make the PR the coherent review unit.

## Verified

The version, source-identity, commit-record, and PR-record regression suites pass on the final branch state.

## Compatibility

- [ ] Internal
- [ ] Fix
- [ ] Additive
- [x] Breaking

## Open / deferred

None.'

printf '%s\n' "$valid" | python3 "$TOOL" --title 'refactor(release)!: use tagged source ancestry' >/dev/null

expect_fail() {
  local title="$1" body="$2"
  if printf '%s\n' "$body" | python3 "$TOOL" --title "$title" >/dev/null 2>&1; then
    echo 'PR record checker unexpectedly accepted an invalid fixture.' >&2
    exit 1
  fi
}

expect_fail 'Versioning cleanup' "$valid"
two_checked="$(printf '%s\n' "$valid" | sed 's/^- \[ \] Additive$/- [x] Additive/')"
expect_fail 'refactor(release): choose one compatibility class' "$two_checked"
expect_fail 'refactor(release): require verified evidence' '## Why

The body has a meaningful reason for the change.

## What

The body has a meaningful final-state summary.

## Verified

none

## Compatibility

- [x] Internal
- [ ] Fix
- [ ] Additive
- [ ] Breaking

## Open / deferred

None.'

echo 'PR record checks passed.'
