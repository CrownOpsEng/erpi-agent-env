#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import pathlib
import shutil
import stat
import tarfile
import tempfile
from typing import Any, NoReturn

ROOT = pathlib.Path(__file__).resolve().parents[1]
CAPSULE_DIR = ROOT / "runtime/node-capsules"
MANIFEST = ROOT / "manifest/node-capsules.json"
MARKER = ".agent-env-node-deps.json"
MARKER_SCHEMA = 2
STAGE_PREFIX = ".agent-env-node-deps-stage."
CLEAN_PREFIX = ".agent-env-node-deps-clean."


def die(message: str) -> NoReturn:
    raise SystemExit(message)


def lexists(path: pathlib.Path) -> bool:
    return os.path.lexists(path)


def sri_ok(path: pathlib.Path, sri: str) -> bool:
    algo, expected = sri.split("-", 1)
    h = hashlib.new(algo)
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return base64.b64encode(h.digest()).decode() == expected


def sha256_file(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def safe_members(tf: tarfile.TarFile):
    for member in tf.getmembers():
        pure = pathlib.PurePosixPath(member.name)
        if pure.is_absolute() or ".." in pure.parts or not pure.parts or pure.parts[0] != "package":
            raise RuntimeError(f"unsafe archive member: {member.name}")
        if not (member.isdir() or member.isfile()):
            raise RuntimeError(f"unsupported archive member type: {member.name}")
        yield member


def lock_entry(lock: dict[str, Any], name: str) -> dict[str, Any] | None:
    packages = lock.get("packages") or {}
    return packages.get(f"node_modules/{name}")


def validate_package_name(name: str) -> None:
    parts = name.split("/")
    valid = (len(parts) == 1 and parts[0] and not parts[0].startswith("@")) or (
        len(parts) == 2 and parts[0].startswith("@") and len(parts[0]) > 1 and bool(parts[1])
    )
    if not valid or any(part in (".", "..") for part in parts):
        die(f"unsafe package name in immutable capsule manifest: {name!r}")


def package_dest(repo: pathlib.Path, name: str) -> pathlib.Path:
    validate_package_name(name)
    return repo / "node_modules" / pathlib.Path(*name.split("/"))


def load_manifest() -> dict[str, Any]:
    data = json.loads(MANIFEST.read_text(encoding="utf-8"))
    packages = data.get("packages")
    if data.get("schema") != 1 or not isinstance(packages, dict):
        die(f"invalid immutable capsule manifest: {MANIFEST}")
    for name, record in packages.items():
        validate_package_name(name)
        if not isinstance(record, dict):
            die(f"invalid immutable capsule manifest record for {name!r}")
        for key in ("version", "file", "sha256", "integrity"):
            if not isinstance(record.get(key), str) or not record[key]:
                die(f"invalid immutable capsule manifest record for {name!r}: missing {key}")
    return data


def load_lock(repo: pathlib.Path) -> dict[str, Any]:
    path = repo / "package-lock.json"
    if not path.is_file() or path.is_symlink():
        die("package-lock.json is required as a regular repository file; repository lock remains authority.")
    if not path.resolve().is_relative_to(repo):
        die(f"package-lock.json escapes repository: {path}")
    return json.loads(path.read_text(encoding="utf-8"))


def ensure_directory_path(path: pathlib.Path, repo: pathlib.Path, *, label: str) -> None:
    if not path.is_relative_to(repo):
        die(f"{label} is outside repository: {path}")
    current = repo
    for part in path.relative_to(repo).parts:
        current = current / part
        if not lexists(current):
            continue
        if current.is_symlink():
            die(f"refusing symlinked {label}: {current}")
        if not current.is_dir():
            die(f"refusing non-directory {label}: {current}")
    resolved = path.resolve(strict=False)
    if not resolved.is_relative_to(repo):
        die(f"{label} resolves outside repository: {path} -> {resolved}")


def ensure_package_target(repo: pathlib.Path, name: str) -> pathlib.Path:
    node_modules = repo / "node_modules"
    ensure_directory_path(node_modules, repo, label="node_modules path")
    dest = package_dest(repo, name)
    ensure_directory_path(dest.parent, repo, label=f"parent path for {name}")
    if not dest.resolve(strict=False).is_relative_to(repo):
        die(f"package destination resolves outside repository: {dest}")
    if dest.is_symlink():
        die(f"refusing symlinked package destination: {dest}")
    return dest


def package_tree_sha256(path: pathlib.Path) -> str:
    if not path.is_dir() or path.is_symlink():
        die(f"cannot fingerprint non-directory package: {path}")
    root = path.resolve()
    h = hashlib.sha256()
    for entry in sorted(path.rglob("*"), key=lambda item: item.relative_to(path).as_posix()):
        if entry.is_symlink():
            die(f"refusing symlink inside hydrated package: {entry}")
        resolved = entry.resolve()
        if not resolved.is_relative_to(root):
            die(f"package entry escapes package root: {entry}")
        st = entry.stat()
        rel = entry.relative_to(path).as_posix().encode("utf-8")
        mode = stat.S_IMODE(st.st_mode)
        if entry.is_dir():
            h.update(b"D\0" + rel + b"\0" + f"{mode:o}".encode("ascii") + b"\0")
        elif entry.is_file():
            h.update(b"F\0" + rel + b"\0" + f"{mode:o}".encode("ascii") + b"\0")
            with entry.open("rb") as handle:
                for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                    h.update(chunk)
            h.update(b"\0")
        else:
            die(f"unsupported filesystem entry in hydrated package: {entry}")
    return h.hexdigest()


def read_package_meta(dest: pathlib.Path) -> dict[str, Any]:
    package_json = dest / "package.json"
    if not package_json.is_file() or package_json.is_symlink():
        die(f"refusing package without regular package.json: {dest}")
    return json.loads(package_json.read_text(encoding="utf-8"))


def load_marker(node_modules: pathlib.Path) -> dict[str, Any]:
    manifest = load_manifest()
    marker = node_modules / MARKER
    if not lexists(marker):
        return {"schema": MARKER_SCHEMA, "packages": {}}
    if marker.is_symlink() or not marker.is_file():
        die(f"invalid ownership marker path: {marker}")
    try:
        data = json.loads(marker.read_text(encoding="utf-8"))
    except Exception as exc:
        die(f"invalid ownership marker: {marker}: {exc}")
    if data.get("schema") != MARKER_SCHEMA or not isinstance(data.get("packages"), dict):
        die(f"unsupported ownership marker schema; refusing unsafe legacy/stale marker: {marker}")
    for name, record in data["packages"].items():
        if not isinstance(name, str) or not isinstance(record, dict):
            die(f"invalid ownership marker record for {name!r}")
        validate_package_name(name)
        for key in ("version", "capsule_sha256", "tree_sha256"):
            if not isinstance(record.get(key), str) or not record[key]:
                die(f"invalid ownership marker record for {name!r}: missing {key}")
        cap = manifest["packages"].get(name)
        if cap is None or record["version"] != cap["version"] or record["capsule_sha256"] != cap["sha256"]:
            die(f"ownership marker does not match immutable capsule authority for {name!r}")
    return data


def write_marker_atomic(node_modules: pathlib.Path, data: dict[str, Any]) -> None:
    marker = node_modules / MARKER
    tmp = node_modules / f"{MARKER}.tmp.{os.getpid()}"
    if lexists(tmp):
        die(f"refusing pre-existing marker temp path: {tmp}")
    try:
        with tmp.open("w", encoding="utf-8") as handle:
            handle.write(json.dumps(data, indent=2, sort_keys=True) + "\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp, marker)
        dir_fd = os.open(node_modules, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(dir_fd)
        finally:
            os.close(dir_fd)
    finally:
        if lexists(tmp):
            tmp.unlink()


def inspect(repo: pathlib.Path) -> tuple[list[tuple[str, dict[str, Any], pathlib.Path]], list[str]]:
    manifest = load_manifest()
    lock = load_lock(repo)
    ready: list[tuple[str, dict[str, Any], pathlib.Path]] = []
    problems: list[str] = []
    for name, cap in manifest["packages"].items():
        entry = lock_entry(lock, name)
        if not entry:
            continue
        if entry.get("version") != cap["version"] or entry.get("integrity") != cap["integrity"]:
            problems.append(f"{name}: lock mismatch (expected {cap['version']} and pinned integrity)")
            continue
        archive = CAPSULE_DIR / cap["file"]
        actual = sha256_file(archive)
        if actual != cap["sha256"] or not sri_ok(archive, cap["integrity"]):
            problems.append(f"{name}: capsule integrity failure")
            continue
        ready.append((name, cap, archive))
    return ready, problems


def validate_owned(repo: pathlib.Path, marker_data: dict[str, Any]) -> None:
    for name, record in marker_data["packages"].items():
        dest = ensure_package_target(repo, name)
        if not dest.is_dir() or dest.is_symlink():
            die(f"owned package is missing or unsafe; refusing to continue: {dest}")
        meta = read_package_meta(dest)
        if meta.get("name") != name or meta.get("version") != record["version"]:
            die(f"owned package metadata changed; refusing to continue: {dest}")
        actual = package_tree_sha256(dest)
        if actual != record["tree_sha256"]:
            die(f"owned package contents changed; refusing to continue: {dest}")


def cmd_status(repo: pathlib.Path) -> int:
    ready, problems = inspect(repo)
    node_modules = repo / "node_modules"
    marker_data = {"schema": MARKER_SCHEMA, "packages": {}}
    if lexists(node_modules):
        ensure_directory_path(node_modules, repo, label="node_modules path")
        marker_data = load_marker(node_modules)
        validate_owned(repo, marker_data)
    for name, cap, _ in ready:
        dest = ensure_package_target(repo, name)
        if name in marker_data["packages"]:
            state = "owned"
        elif dest.is_dir() and not dest.is_symlink() and (dest / "package.json").is_file():
            state = "present"
        else:
            state = "available"
        print(f"{name}@{cap['version']}: {state}")
    for problem in problems:
        print(f"ERROR {problem}")
    return 1 if problems else 0


def extract_capsule(archive: pathlib.Path, stage_dest: pathlib.Path, name: str, cap: dict[str, Any]) -> str:
    stage_dest.mkdir(mode=0o700)
    with tarfile.open(archive, "r:gz") as tf:
        members = list(safe_members(tf))
        tf.extractall(stage_dest, members=members, filter="data")
    package_dir = stage_dest / "package"
    meta = read_package_meta(package_dir)
    if meta.get("name") != name or meta.get("version") != cap["version"]:
        die(f"capsule metadata mismatch for {name}")
    return package_tree_sha256(package_dir)


def cmd_hydrate(repo: pathlib.Path) -> int:
    ready, problems = inspect(repo)
    if problems:
        for problem in problems:
            print(f"ERROR {problem}")
        return 1

    node_modules = repo / "node_modules"
    ensure_directory_path(node_modules, repo, label="node_modules path")

    # Preflight every package and every existing ownership record before making
    # any repository change. This prevents a late foreign-path conflict from
    # leaving earlier packages partially hydrated.
    marker_data = {"schema": MARKER_SCHEMA, "packages": {}}
    if lexists(node_modules):
        marker_data = load_marker(node_modules)
        validate_owned(repo, marker_data)

    missing: list[tuple[str, dict[str, Any], pathlib.Path, pathlib.Path]] = []
    for name, cap, archive in ready:
        dest = ensure_package_target(repo, name)
        if lexists(dest):
            if not dest.is_dir() or dest.is_symlink():
                die(f"refusing to overwrite foreign path: {dest}")
            meta = read_package_meta(dest)
            if meta.get("name") != name or meta.get("version") != cap["version"]:
                die(f"refusing to overwrite mismatching package: {dest}")
            if name in marker_data["packages"]:
                print(f"{name}@{cap['version']}: already hydrated")
            else:
                print(f"{name}@{cap['version']}: already present")
            continue
        missing.append((name, cap, archive, dest))

    if not missing:
        return 0

    created_node_modules = False
    if not lexists(node_modules):
        node_modules.mkdir(mode=0o755)
        created_node_modules = True
    ensure_directory_path(node_modules, repo, label="node_modules path")

    stage_root = pathlib.Path(tempfile.mkdtemp(prefix=STAGE_PREFIX, dir=node_modules))
    staged: list[tuple[str, dict[str, Any], pathlib.Path, pathlib.Path, str]] = []
    committed: list[pathlib.Path] = []
    new_records = dict(marker_data["packages"])
    try:
        for index, (name, cap, archive, dest) in enumerate(missing):
            stage_dest = stage_root / str(index)
            tree_sha = extract_capsule(archive, stage_dest, name, cap)
            staged.append((name, cap, stage_dest / "package", dest, tree_sha))

        # Re-check every destination immediately before commit. All capsule
        # extraction has already succeeded at this point.
        for name, _, _, dest, _ in staged:
            ensure_package_target(repo, name)
            if lexists(dest):
                die(f"package destination changed during hydration; refusing partial commit: {dest}")

        try:
            for name, cap, package_dir, dest, tree_sha in staged:
                dest.parent.mkdir(parents=True, exist_ok=True)
                ensure_package_target(repo, name)
                if lexists(dest):
                    die(f"package destination changed during hydration: {dest}")
                package_dir.rename(dest)
                committed.append(dest)
                new_records[name] = {
                    "version": cap["version"],
                    "capsule_sha256": cap["sha256"],
                    "tree_sha256": tree_sha,
                }
                print(f"{name}@{cap['version']}: hydrated")
            write_marker_atomic(node_modules, {"schema": MARKER_SCHEMA, "packages": new_records})
        except BaseException:
            for dest in reversed(committed):
                if dest.is_dir() and not dest.is_symlink():
                    shutil.rmtree(dest)
            raise
    finally:
        shutil.rmtree(stage_root, ignore_errors=True)
        if created_node_modules:
            try:
                node_modules.rmdir()
            except OSError:
                pass
    return 0


def cmd_clean(repo: pathlib.Path) -> int:
    node_modules = repo / "node_modules"
    if not lexists(node_modules):
        print("No agent-env hydrated packages recorded.")
        return 0
    ensure_directory_path(node_modules, repo, label="node_modules path")
    marker = node_modules / MARKER
    if not lexists(marker):
        print("No agent-env hydrated packages recorded.")
        return 0

    marker_data = load_marker(node_modules)
    validate_owned(repo, marker_data)
    names = sorted(marker_data["packages"])
    if not names:
        marker.unlink()
        print("No agent-env hydrated packages recorded.")
        return 0

    # Move all owned packages into one same-filesystem quarantine first. If any
    # rename fails, restore the already-moved packages and leave the marker.
    clean_root = pathlib.Path(tempfile.mkdtemp(prefix=CLEAN_PREFIX, dir=node_modules))
    moved: list[tuple[str, pathlib.Path, pathlib.Path]] = []
    try:
        try:
            for index, name in enumerate(names):
                dest = ensure_package_target(repo, name)
                record = marker_data["packages"][name]
                if package_tree_sha256(dest) != record["tree_sha256"]:
                    die(f"owned package changed during cleanup; refusing partial cleanup: {dest}")
                quarantine = clean_root / str(index)
                dest.rename(quarantine)
                moved.append((name, dest, quarantine))
            marker.unlink()
        except BaseException:
            for _, dest, quarantine in reversed(moved):
                if lexists(quarantine) and not lexists(dest):
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    quarantine.rename(dest)
            raise
        for name, _, _ in moved:
            print(f"removed {name}")
    finally:
        shutil.rmtree(clean_root, ignore_errors=True)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Hydrate exact repository-locked Node packages from immutable offline capsules without editing manifests."
    )
    parser.add_argument("--repo", default=".")
    sub = parser.add_subparsers(dest="cmd", required=True)
    for name in ("status", "hydrate", "clean"):
        sub.add_parser(name)
    ns = parser.parse_args()
    repo = pathlib.Path(ns.repo).resolve()
    if not repo.is_dir():
        die(f"repository path is not a directory: {repo}")
    return {"status": cmd_status, "hydrate": cmd_hydrate, "clean": cmd_clean}[ns.cmd](repo)


if __name__ == "__main__":
    raise SystemExit(main())
