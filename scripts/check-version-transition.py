#!/usr/bin/env python3
"""Validate product-version transitions independently of commit labels."""

from __future__ import annotations

import argparse
import re
from dataclasses import dataclass

VERSION_RE = re.compile(
    r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
    r"(?:-(alpha|beta|rc)\.([1-9][0-9]*)(?:-([1-9][0-9]*))?)?$"
)
STAGE_RANK = {"alpha": 0, "beta": 1, "rc": 2, None: 3}


@dataclass(frozen=True)
class Version:
    major: int
    minor: int
    patch: int
    stage: str | None
    serial: int
    revision: int | None

    @property
    def release_key(self) -> tuple[int, int, int, int, int]:
        return (
            self.major,
            self.minor,
            self.patch,
            STAGE_RANK[self.stage],
            self.serial,
        )

    @property
    def is_candidate_build(self) -> bool:
        return self.revision is not None

    @property
    def release_version(self) -> str:
        base = f"{self.major}.{self.minor}.{self.patch}"
        if self.stage is not None:
            base += f"-{self.stage}.{self.serial}"
        return base


def parse(text: str) -> Version:
    match = VERSION_RE.fullmatch(text)
    if not match:
        raise SystemExit(
            f"Invalid PRODUCT_VERSION {text!r}; use stable SemVer, alpha.N/beta.N/rc.N, "
            "or a prerelease candidate-build revision such as rc.1-1"
        )
    stage = match.group(4)
    return Version(
        int(match.group(1)),
        int(match.group(2)),
        int(match.group(3)),
        stage,
        int(match.group(5)) if stage else 0,
        int(match.group(6)) if match.group(6) else None,
    )


def validate(parent: str, current: str, metadata_only: bool) -> None:
    parent_version = parse(parent)
    current_version = parse(current)

    if current == parent:
        return

    # Candidate-build revisions describe real development iterations after an
    # already published alpha/beta/RC. They may advance with the source change
    # they identify and are never themselves release cuts.
    if current_version.is_candidate_build:
        if current_version.release_key != parent_version.release_key:
            raise SystemExit(
                "A candidate-build revision may only advance on the same published prerelease line"
            )
        parent_revision = parent_version.revision or 0
        if current_version.revision <= parent_revision:
            raise SystemExit(
                f"Candidate-build revision must move forward: {parent} -> {current}"
            )
        return

    # Returning from a development revision to the same already-published
    # prerelease would attempt to reuse an immutable release identity.
    if parent_version.is_candidate_build and current_version.release_key == parent_version.release_key:
        raise SystemExit(
            f"Cannot collapse development build {parent} back onto published prerelease {current}"
        )

    if not metadata_only:
        raise SystemExit(
            "Changing the released compatibility version is release metadata work and may not be mixed with runtime/source changes"
        )

    if current_version.release_key <= parent_version.release_key:
        raise SystemExit(
            f"PRODUCT_VERSION must move forward: {parent} -> {current} is not a forward release transition"
        )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--parent-version", required=True)
    parser.add_argument("--current-version", required=True)
    parser.add_argument("--metadata-only", required=True, choices=("true", "false"))
    args = parser.parse_args()
    validate(args.parent_version, args.current_version, args.metadata_only == "true")
    print("Version transition check passed.")


if __name__ == "__main__":
    main()
