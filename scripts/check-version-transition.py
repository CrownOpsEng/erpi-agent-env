#!/usr/bin/env python3
"""Validate product-version transitions independently of commit labels."""

from __future__ import annotations

import argparse
import re
from dataclasses import dataclass

VERSION_RE = re.compile(
    r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
    r"(?:-(alpha|beta|rc)\.([1-9][0-9]*))?$"
)
STAGE_RANK = {"alpha": 0, "beta": 1, "rc": 2, None: 3}


@dataclass(frozen=True)
class Version:
    major: int
    minor: int
    patch: int
    stage: str | None
    serial: int

    @property
    def order_key(self) -> tuple[int, int, int, int, int]:
        return (
            self.major,
            self.minor,
            self.patch,
            STAGE_RANK[self.stage],
            self.serial,
        )


def parse(text: str) -> Version:
    match = VERSION_RE.fullmatch(text)
    if not match:
        raise SystemExit(
            f"Invalid PRODUCT_VERSION {text!r}; use stable SemVer or alpha.N/beta.N/rc.N prerelease syntax"
        )
    stage = match.group(4)
    return Version(
        int(match.group(1)),
        int(match.group(2)),
        int(match.group(3)),
        stage,
        int(match.group(5)) if stage else 0,
    )


def validate(parent: str, current: str) -> None:
    parent_version = parse(parent)
    current_version = parse(current)

    if current == parent:
        return

    if current_version.order_key <= parent_version.order_key:
        raise SystemExit(
            f"PRODUCT_VERSION must move forward: {parent} -> {current} is not a forward SemVer transition"
        )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--parent-version", required=True)
    parser.add_argument("--current-version", required=True)
    args = parser.parse_args()
    validate(args.parent_version, args.current_version)
    print("Version transition check passed.")


if __name__ == "__main__":
    main()
