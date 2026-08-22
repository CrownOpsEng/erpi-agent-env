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
