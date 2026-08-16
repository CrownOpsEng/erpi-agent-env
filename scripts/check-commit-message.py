#!/usr/bin/env python3
"""Validate the repository's detailed direct-to-main commit message contract."""

from __future__ import annotations

import re
import sys

SUBJECT_RE = re.compile(
    r"^(feat|fix|perf|refactor|test|docs|ci|chore)"
    r"(?:\([a-z0-9][a-z0-9-]*\))?!?: [^\s].+$"
)
SECTIONS = ("Why:", "What:", "Validation:")


def fail(message: str) -> None:
    print(f"Commit message policy: {message}", file=sys.stderr)
    raise SystemExit(1)


def validate(message: str) -> None:
    lines = message.rstrip("\n").splitlines()
    if not lines or not lines[0].strip():
        fail("missing subject")

    subject = lines[0]
    if len(subject) > 72:
        fail(f"subject is {len(subject)} characters; maximum is 72")
    if not SUBJECT_RE.fullmatch(subject):
        fail("subject must use Conventional Commits: type(scope): imperative summary")

    if len(lines) < 3 or lines[1] != "":
        fail("subject must be followed by a blank line and a detailed body")

    body = lines[2:]
    positions: list[int] = []
    for heading in SECTIONS:
        try:
            positions.append(body.index(heading))
        except ValueError:
            fail(f"missing required body section {heading}")

    if positions != sorted(positions) or len(set(positions)) != len(SECTIONS):
        fail("body sections must appear once in Why, What, Validation order")

    for index, heading in enumerate(SECTIONS):
        start = positions[index] + 1
        end = positions[index + 1] if index + 1 < len(SECTIONS) else len(body)
        content = " ".join(line.strip() for line in body[start:end] if line.strip())
        if len(content) < 12:
            fail(f"{heading} needs a meaningful explanation, not a placeholder")


def main() -> None:
    validate(sys.stdin.read())
    print("Detailed commit message check passed.")


if __name__ == "__main__":
    main()
