#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
CHECKER="$ROOT/scripts/check-commit-message.py"

valid='fix(repo): enforce detailed commit history

Why:
The repository is intended to teach from its history, so terse subjects alone are not enough context for future review.

What:
Require structured rationale, implementation impact, and validation evidence on every direct-to-main commit.

Validation:
The commit-message policy is exercised here with valid and invalid fixtures and is also checked by the Validate workflow.'

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

Validation:
The fixture expects a nonzero exit status.'
expect_fail 'fix(repo): missing validation section

Why:
The body has a reason and implementation details.

What:
The validation section is deliberately absent.'
expect_fail 'fix(repo): placeholder body

Why:
ok

What:
ok

Validation:
ok'

echo "Detailed commit-message policy checks passed."
