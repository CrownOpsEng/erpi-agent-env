#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
CHECKER="$ROOT/scripts/check-commit-message.py"

valid='fix(repo): enforce semantic checkpoint records

Why:
The repository history is cold context for future review and resumption, so checkpoint commits need enough rationale to remain useful without loading unrelated guidance.

What:
Require concise Conventional Commit subjects plus final-state Why, What, and Verified evidence, with optional Impact when compatibility or operations matter.

Verified:
The commit-message policy is exercised here with valid and invalid fixtures.

Impact:
This changes repository contribution records but not the runtime contract.'

printf '%s\n' "$valid" | python3 "$CHECKER" >/dev/null

expect_fail() {
  local message="$1"
  if printf '%s\n' "$message" | python3 "$CHECKER" >/dev/null 2>&1; then
    echo "Commit-message checker unexpectedly accepted an invalid fixture." >&2
    exit 1
  fi
}


for version in 0.4.0 0.4.0-alpha.1 0.4.0-beta.2 0.4.0-rc.3; do
  release="chore(release): promote v${version}"
  printf '%s\n' "$release" | python3 "$CHECKER" --release-promotion-version "$version" >/dev/null
done
release='chore(release): promote v0.4.0'

if printf '%s\n' "$release" | python3 "$CHECKER" >/dev/null 2>&1; then
  echo "Detailed commit-message checker unexpectedly accepted a terse release promotion without release context." >&2
  exit 1
fi
if printf '%s\n' 'chore(release): promote v0.4.1' | python3 "$CHECKER" --release-promotion-version 0.4.0 >/dev/null 2>&1; then
  echo "Release promotion checker accepted the wrong promoted version." >&2
  exit 1
fi
if printf '%s\n' 'chore(release): promote v0.4.0-rc.1-1' | python3 "$CHECKER" --release-promotion-version 0.4.0-rc.1-1 >/dev/null 2>&1; then
  echo "Release promotion checker accepted a revisioned development build as a clean release." >&2
  exit 1
fi
if printf '%s\n\nWhy:\nextra body' "$release" | python3 "$CHECKER" --release-promotion-version 0.4.0 >/dev/null 2>&1; then
  echo "Release promotion checker accepted an unexpected body." >&2
  exit 1
fi

expect_fail 'fix(repo): terse subject only'
expect_fail 'Fix repository policy

Why:
This subject does not use Conventional Commits.

What:
It should be rejected by the policy checker.

Verified:
The fixture expects a nonzero exit status.'
expect_fail 'fix(repo): missing verified section

Why:
The body has a reason and implementation details.

What:
The verified evidence section is deliberately absent.'
expect_fail 'fix(repo): obsolete validation heading

Why:
The body is otherwise structurally complete.

What:
This fixture deliberately uses the superseded heading.

Validation:
The old heading must no longer satisfy the record contract.'
expect_fail 'fix(repo): placeholder body

Why:
ok

What:
ok

Verified:
ok'

echo "Detailed commit-message policy checks passed."
