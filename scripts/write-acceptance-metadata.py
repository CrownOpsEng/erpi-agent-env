#!/usr/bin/env python3
"""Write machine-readable acceptance metadata for a completed distribution build."""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import subprocess


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--versions", default="versions.env")
    parser.add_argument("--sidecar", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--source-sha", required=True)
    parser.add_argument("--source-base-tag", required=True)
    parser.add_argument("--source-distance", required=True, type=int)
    parser.add_argument("--source-description", required=True)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--workflow", required=True)
    parser.add_argument("--run-id", required=True, type=int)
    parser.add_argument("--run-attempt", required=True, type=int)
    parser.add_argument("--event", required=True)
    parser.add_argument("--release-tag", default="")
    return parser.parse_args()


def quoted_env_value(text: str, name: str) -> str:
    match = re.search(rf'^{re.escape(name)}="([^"]+)"$', text, flags=re.MULTILINE)
    if not match:
        raise SystemExit(f"Missing {name} in versions file")
    return match.group(1)


def derive_artifact_stem(
    product_version: str,
    source_sha: str,
    source_base_tag: str,
    source_distance: int,
    source_description: str,
    target: str,
) -> str:
    tool = pathlib.Path(__file__).with_name("build-identity.sh")
    try:
        result = subprocess.run(
            [
                str(tool),
                product_version,
                source_sha,
                source_base_tag,
                str(source_distance),
                source_description,
                target,
            ],
            check=True,
            capture_output=True,
            text=True,
        )
    except subprocess.CalledProcessError as exc:
        raise SystemExit(exc.stderr.strip() or "Source identity derivation failed") from exc
    fields = dict(line.split("=", 1) for line in result.stdout.splitlines() if "=" in line)
    expected = {
        "product_version",
        "source_commit",
        "source_base_tag",
        "source_distance",
        "source_description",
        "artifact_stem",
    }
    if set(fields) != expected:
        raise SystemExit(f"Malformed source identity output: {result.stdout!r}")
    return fields["artifact_stem"]


def main() -> None:
    args = parse_args()
    versions_path = pathlib.Path(args.versions)
    sidecar_path = pathlib.Path(args.sidecar)
    output_path = pathlib.Path(args.output)

    versions = versions_path.read_text(encoding="utf-8")
    product_version = quoted_env_value(versions, "PRODUCT_VERSION")
    target = quoted_env_value(versions, "TARGET")
    artifact_stem = derive_artifact_stem(
        product_version,
        args.source_sha,
        args.source_base_tag,
        args.source_distance,
        args.source_description,
        target,
    )

    fields = sidecar_path.read_text(encoding="utf-8").strip().split()
    if len(fields) != 2 or not re.fullmatch(r"[0-9a-f]{64}", fields[0]):
        raise SystemExit(f"Malformed SHA-256 sidecar: {sidecar_path}")
    digest, filename = fields
    expected_filename = f"{artifact_stem}.tar.gz"
    if filename != expected_filename:
        raise SystemExit(
            f"Artifact filename {filename!r} does not match product/build version {product_version!r}; expected {expected_filename!r}"
        )

    artifact_path = sidecar_path.parent / filename
    if not artifact_path.is_file():
        raise SystemExit(f"Artifact named by sidecar does not exist: {artifact_path}")

    if args.release_tag:
        if re.fullmatch(r"\d+\.\d+\.\d+-(?:alpha|beta|rc)\.[1-9]\d*-[1-9]\d*", product_version):
            raise SystemExit("Candidate-build revisions are qualification artifacts, not release tags")
        expected_tag = f"v{product_version}"
        if args.release_tag != expected_tag:
            raise SystemExit(
                f"Release tag {args.release_tag!r} does not match product version {expected_tag!r}"
            )
        if args.source_distance != 0 or args.source_description != args.release_tag:
            raise SystemExit("Release acceptance must be built from the exact release/prerelease tag")

    metadata = {
        "schema_version": 2,
        "status": "accepted",
        "product_version": product_version,
        "target": target,
        "source": {
            "commit": args.source_sha,
            "description": args.source_description,
            "base_tag": args.source_base_tag,
            "distance": args.source_distance,
        },
        "repository": args.repository,
        "workflow": {
            "name": args.workflow,
            "run_id": args.run_id,
            "run_attempt": args.run_attempt,
            "event": args.event,
        },
        "artifact": {
            "filename": filename,
            "sha256": digest,
            "size_bytes": artifact_path.stat().st_size,
        },
        "release_tag": args.release_tag or None,
    }

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
