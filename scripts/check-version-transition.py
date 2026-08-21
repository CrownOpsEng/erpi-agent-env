#!/usr/bin/env python3
"""Validate lifecycle-version transitions independently of commit labels."""

from __future__ import annotations

import argparse
import re

VERSION_RE = re.compile(
    r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
    r"(?:(-dev)|-rc\.([1-9][0-9]*))?$"
)


def parse(version: str) -> tuple[str, str]:
    match = VERSION_RE.fullmatch(version)
    if not match:
        raise SystemExit(f"Invalid lifecycle version: {version}")
    base = ".".join(match.group(i) for i in range(1, 4))
    if match.group(4):
        return "dev", base
    if match.group(5):
        return "rc", base
    return "stable", base


def validate(parent: str, current: str, version_only: bool) -> None:
    parent_kind, parent_base = parse(parent)
    current_kind, current_base = parse(current)

    if current == parent:
        if current_kind != "dev":
            raise SystemExit(
                f"Immutable {current_kind} identity {current} cannot name a second source commit"
            )
        return

    if current_kind == "rc":
        if parent_kind != "dev" or parent_base != current_base:
            raise SystemExit(
                f"Release candidate {current} must be cut from matching {current_base}-dev"
            )
        if not version_only:
            raise SystemExit("Cutting a release candidate must be a version-only source change")
        return

    if current_kind == "stable":
        if parent_kind != "rc" or parent_base != current_base:
            raise SystemExit(
                f"Stable {current} must finalize a matching {current_base}-rc.N candidate"
            )
        if not version_only:
            raise SystemExit("Finalizing a stable release must be a version-only source change")
        return

    if parent_kind == "rc":
        if current_kind != "dev" or current_base != parent_base:
            raise SystemExit(
                f"Rejected candidate {parent} must return to matching {parent_base}-dev before further changes"
            )
        return

    # Development target changes and stable -> next development target require
    # semantic judgment, so they remain policy/review decisions rather than a
    # mechanical guess based on diff size or commit type.


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--parent-version", required=True)
    parser.add_argument("--current-version", required=True)
    parser.add_argument("--version-only", required=True, choices=("true", "false"))
    args = parser.parse_args()
    validate(args.parent_version, args.current_version, args.version_only == "true")
    print("Version transition check passed.")


if __name__ == "__main__":
    main()
