#!/usr/bin/env python3
import csv
from pathlib import Path
import sys


def normalize(env_root: Path) -> None:
    site_candidates = sorted((env_root / "lib").glob("python*/site-packages"))
    if len(site_candidates) != 1:
        raise SystemExit(f"Expected exactly one venv site-packages directory; found {site_candidates}")
    site = site_candidates[0]
    for dist in sorted(site.glob("*.dist-info")):
        cache = dist / "uv_cache.json"
        record = dist / "RECORD"
        cache_record = f"{dist.name}/uv_cache.json"
        if cache.exists() or cache.is_symlink():
            cache.unlink()
        if record.is_file():
            with record.open("r", encoding="utf-8", newline="") as handle:
                rows = list(csv.reader(handle))
            kept = [row for row in rows if not (row and row[0] == cache_record)]
            if len(kept) != len(rows):
                with record.open("w", encoding="utf-8", newline="") as handle:
                    csv.writer(handle, lineterminator="\n").writerows(kept)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: normalize-python-metadata.py ENV_ROOT")
    normalize(Path(sys.argv[1]).resolve())
