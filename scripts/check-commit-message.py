#!/usr/bin/env python3
"""Validate semantic checkpoint/mainline commit records."""

from __future__ import annotations

import argparse
import re
import sys

SUBJECT_RE = re.compile(
    r"^(feat|fix|perf|refactor|test|docs|ci|chore)"
    r"(?:\([a-z0-9][a-z0-9-]*\))?!?: [^\s].+$"
)
REQUIRED = ("Why:", "What:", "Verified:")
OPTIONAL = "Impact:"
RELEASE_PROMOTION_SUBJECT = "chore(release): promote v{}"
CLEAN_RELEASE_VERSION_RE = re.compile(
    r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
    r"(?:-(?:alpha|beta|rc)\.[1-9][0-9]*)?$"
)


def fail(message: str) -> None:
    print(f"Commit message policy: {message}", file=sys.stderr)
    raise SystemExit(1)


def meaningful(lines: list[str], heading: str) -> None:
    text = " ".join(line.strip() for line in lines if line.strip())
    if len(text) < 12:
        fail(f"{heading} needs a meaningful explanation, not a placeholder")


def validate_release_promotion(message: str, version: str) -> None:
    if not CLEAN_RELEASE_VERSION_RE.fullmatch(version):
        fail(
            "release promotion context requires a clean stable/alpha/beta/rc version, "
            f"not {version}"
        )
    lines = message.rstrip("\n").splitlines()
    expected = RELEASE_PROMOTION_SUBJECT.format(version)
    if lines != [expected]:
        fail(
            "release promotion must be exactly one line: "
            f"{expected}"
        )


def validate(message: str) -> None:
    lines = message.rstrip("\n").splitlines()
    if not lines or not lines[0].strip():
        fail("missing subject")

    subject = lines[0]
    if len(subject) > 72:
        fail(f"subject is {len(subject)} characters; maximum is 72")
    if not SUBJECT_RE.fullmatch(subject):
        fail("subject must use Conventional Commits: type(scope): concise imperative summary")

    if len(lines) < 3 or lines[1] != "":
        fail("subject must be followed by a blank line and a detailed body")

    body = lines[2:]
    if "Validation:" in body:
        fail("use Verified: for evidence actually obtained; Validation: is obsolete")

    positions: dict[str, int] = {}
    for heading in (*REQUIRED, OPTIONAL):
        hits = [i for i, line in enumerate(body) if line == heading]
        if len(hits) > 1:
            fail(f"body section {heading} appears more than once")
        if hits:
            positions[heading] = hits[0]

    for heading in REQUIRED:
        if heading not in positions:
            fail(f"missing required body section {heading}")

    required_positions = [positions[h] for h in REQUIRED]
    if required_positions != sorted(required_positions):
        fail("body sections must appear in Why, What, Verified order")
    if OPTIONAL in positions and positions[OPTIONAL] < positions["Verified:"]:
        fail("Impact: must follow Verified:")

    ordered = [(h, positions[h]) for h in (*REQUIRED, OPTIONAL) if h in positions]
    ordered.sort(key=lambda item: item[1])
    for idx, (heading, pos) in enumerate(ordered):
        end = ordered[idx + 1][1] if idx + 1 < len(ordered) else len(body)
        meaningful(body[pos + 1 : end], heading)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--release-promotion-version",
        help="allow the exact one-line metadata-only promotion subject for this version",
    )
    args = parser.parse_args()
    message = sys.stdin.read()
    if args.release_promotion_version:
        validate_release_promotion(message, args.release_promotion_version)
        print("Release promotion commit message check passed.")
    else:
        validate(message)
        print("Detailed commit message check passed.")


if __name__ == "__main__":
    main()
