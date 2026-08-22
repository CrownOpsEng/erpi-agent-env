#!/usr/bin/env python3
"""Validate that a pull request is a coherent review record."""

from __future__ import annotations

import argparse
import re
import sys

SUBJECT_RE = re.compile(
    r"^(feat|fix|perf|refactor|test|docs|ci|chore)"
    r"(?:\([a-z0-9][a-z0-9-]*\))?!?: [^\s].+$"
)
HEADINGS = ("## Why", "## What", "## Verified", "## Compatibility", "## Open / deferred")
COMPATIBILITY = ("Internal", "Fix", "Additive", "Breaking")
CHECKBOX_RE = re.compile(r"^- \[([ xX])\] (Internal|Fix|Additive|Breaking)\s*$")


def fail(message: str) -> None:
    print(f"PR record policy: {message}", file=sys.stderr)
    raise SystemExit(1)


def section_text(lines: list[str]) -> str:
    return " ".join(line.strip() for line in lines if line.strip())


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--title", required=True)
    args = parser.parse_args()
    body = sys.stdin.read().replace("\r\n", "\n")

    if len(args.title) > 72 or not SUBJECT_RE.fullmatch(args.title):
        fail("title must be a <=72-character Conventional Commit summary suitable for squash integration")

    lines = body.rstrip("\n").splitlines()
    positions: list[int] = []
    for heading in HEADINGS:
        hits = [i for i, line in enumerate(lines) if line.strip() == heading]
        if len(hits) != 1:
            fail(f"body must contain exactly one {heading} section")
        positions.append(hits[0])
    if positions != sorted(positions):
        fail("sections must appear in Why, What, Verified, Compatibility, Open / deferred order")

    sections: dict[str, list[str]] = {}
    for index, heading in enumerate(HEADINGS):
        start = positions[index] + 1
        end = positions[index + 1] if index + 1 < len(positions) else len(lines)
        sections[heading] = lines[start:end]

    for heading in ("## Why", "## What", "## Verified"):
        if len(section_text(sections[heading])) < 12:
            fail(f"{heading} needs a meaningful final-state explanation")

    checked: list[str] = []
    seen: set[str] = set()
    for line in sections["## Compatibility"]:
        match = CHECKBOX_RE.fullmatch(line.strip())
        if not match:
            continue
        label = match.group(2)
        if label in seen:
            fail(f"compatibility option {label} appears more than once")
        seen.add(label)
        if match.group(1).lower() == "x":
            checked.append(label)
    if seen != set(COMPATIBILITY):
        fail("Compatibility must list Internal, Fix, Additive, and Breaking checkboxes")
    if len(checked) != 1:
        fail("exactly one compatibility classification must be selected")

    open_text = section_text(sections["## Open / deferred"])
    if not open_text:
        fail("Open / deferred must say what remains or explicitly say None")

    print(f"PR record check passed ({checked[0]}).")


if __name__ == "__main__":
    main()
