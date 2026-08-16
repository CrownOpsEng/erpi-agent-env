#!/usr/bin/env python3
"""Write machine-readable acceptance metadata for a completed distribution build."""

from __future__ import annotations

import argparse
import json
import pathlib
import re


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--versions", default="versions.env")
    parser.add_argument("--sidecar", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--source-sha", required=True)
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


def main() -> None:
    args = parse_args()
    versions_path = pathlib.Path(args.versions)
    sidecar_path = pathlib.Path(args.sidecar)
    output_path = pathlib.Path(args.output)

    versions = versions_path.read_text(encoding="utf-8")
    bundle_version = quoted_env_value(versions, "BUNDLE_VERSION")
    target = quoted_env_value(versions, "TARGET")

    fields = sidecar_path.read_text(encoding="utf-8").strip().split()
    if len(fields) != 2 or not re.fullmatch(r"[0-9a-f]{64}", fields[0]):
        raise SystemExit(f"Malformed SHA-256 sidecar: {sidecar_path}")
    digest, filename = fields

    artifact_path = sidecar_path.parent / filename
    if not artifact_path.is_file():
        raise SystemExit(f"Artifact named by sidecar does not exist: {artifact_path}")

    metadata = {
        "schema_version": 1,
        "status": "accepted",
        "bundle_version": bundle_version,
        "target": target,
        "source_commit": args.source_sha,
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
