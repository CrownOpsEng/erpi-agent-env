#!/usr/bin/env python3
from __future__ import annotations

import base64
import hashlib
import json
import pathlib
import sys
import tarfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
EXPECTED_VERSION = "15.0.0"
EXPECTED_INTEGRITY = "sha512-z67u4ZhzCL/Tydu1lJARtEZYWbWaN7oYLHbsuzocr6y4N6WZAagG3RQ4FW61V1/0+jImpj293XfrcYnd1qxtPg=="
EXPECTED_URL = "https://registry.npmjs.org/commander/-/commander-15.0.0.tgz"


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, value: str) -> None:
    (ROOT / path).write_text(value, encoding="utf-8")


def replace_once(path: str, old: str, new: str) -> None:
    value = read(path)
    count = value.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one occurrence, found {count}: {old!r}")
    write(path, value.replace(old, new, 1))


def inspect_archive(archive: pathlib.Path) -> tuple[str, str]:
    data = archive.read_bytes()
    sha256 = hashlib.sha256(data).hexdigest()
    integrity = "sha512-" + base64.b64encode(hashlib.sha512(data).digest()).decode("ascii")
    if integrity != EXPECTED_INTEGRITY:
        raise SystemExit(f"Commander npm integrity mismatch: {integrity}")

    with tarfile.open(archive, mode="r:gz") as tf:
        package_file = tf.extractfile("package/package.json")
        license_file = tf.extractfile("package/LICENSE")
        if package_file is None or license_file is None:
            raise SystemExit("Commander archive is missing package metadata or LICENSE")
        package = json.load(package_file)
        license_text = license_file.read().decode("utf-8")

    expected = {
        "name": "commander",
        "version": EXPECTED_VERSION,
        "license": "MIT",
        "type": "module",
    }
    for key, value in expected.items():
        if package.get(key) != value:
            raise SystemExit(f"Commander package metadata mismatch for {key}: {package.get(key)!r}")
    if package.get("engines", {}).get("node") != ">=22.12.0":
        raise SystemExit(f"Unexpected Commander Node engine: {package.get('engines')!r}")
    if package.get("dependencies"):
        raise SystemExit(f"Commander unexpectedly has runtime dependencies: {package['dependencies']!r}")
    if not license_text.startswith("(The MIT License)\n\nCopyright (c) 2011 TJ Holowaychuk"):
        raise SystemExit("Commander license text did not match the expected upstream license")
    return sha256, license_text


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit("usage: prepare-commander-capsule.py COMMANDER_TGZ")
    archive = pathlib.Path(sys.argv[1])
    if not archive.is_file():
        raise SystemExit(f"Commander archive not found: {archive}")

    sha256, license_text = inspect_archive(archive)
    print(f"Commander {EXPECTED_VERSION} SHA-256: {sha256}")

    versions = read("versions.env")
    if "COMMANDER_VERSION=" in versions or "COMMANDER_SHA256=" in versions:
        raise SystemExit("versions.env already contains Commander pins")
    anchor = 'PURE_RAND_SHA256="3ce449c758cb2ea0db7ff30a1b378d381d9e74681acec74e1e2591ea6aa381ca"\n'
    if versions.count(anchor) != 1:
        raise SystemExit("versions.env pure-rand anchor changed")
    write(
        "versions.env",
        versions.replace(
            anchor,
            anchor + f'COMMANDER_VERSION="{EXPECTED_VERSION}"\nCOMMANDER_SHA256="{sha256}"\n',
            1,
        ),
    )

    manifest_path = ROOT / "vendor/node-capsules/manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    packages = manifest.get("packages")
    if not isinstance(packages, dict) or "commander" in packages:
        raise SystemExit("Node capsule manifest shape changed or Commander already exists")
    packages["commander"] = {
        "component": "commander",
        "version": EXPECTED_VERSION,
        "file": f"commander-{EXPECTED_VERSION}.tgz",
        "sha256": sha256,
        "integrity": EXPECTED_INTEGRITY,
        "url": EXPECTED_URL,
    }
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

    replace_once(
        "build.sh",
        '  "$PURE_RAND_VERSION" "$PURE_RAND_SHA256" <<\'PY_NODE_MANIFEST\'\n',
        '  "$PURE_RAND_VERSION" "$PURE_RAND_SHA256" \\\n  "$COMMANDER_VERSION" "$COMMANDER_SHA256" <<\'PY_NODE_MANIFEST\'\n',
    )
    replace_once(
        "build.sh",
        "    'pure-rand': ('pure-rand', values[8], f'pure-rand-{values[8]}.tgz', values[9]),\n",
        "    'pure-rand': ('pure-rand', values[8], f'pure-rand-{values[8]}.tgz', values[9]),\n    'commander': ('commander', values[10], f'commander-{values[10]}.tgz', values[11]),\n",
    )
    replace_once(
        "build.sh",
        '"node_capsules": {"yaml": "$YAML_VERSION", "postgres": "$POSTGRES_JS_VERSION", "@postgres-language-server/wasm": "$PGLS_WASM_VERSION", "fast-check": "$FAST_CHECK_VERSION", "pure-rand": "$PURE_RAND_VERSION"},',
        '"node_capsules": {"yaml": "$YAML_VERSION", "postgres": "$POSTGRES_JS_VERSION", "@postgres-language-server/wasm": "$PGLS_WASM_VERSION", "fast-check": "$FAST_CHECK_VERSION", "pure-rand": "$PURE_RAND_VERSION", "commander": "$COMMANDER_VERSION"},',
    )

    replace_once(
        "tests/static-check.sh",
        "    'pure-rand': ('pure-rand', vals['PURE_RAND_VERSION'], f\"pure-rand-{vals['PURE_RAND_VERSION']}.tgz\", vals['PURE_RAND_SHA256']),\n",
        "    'pure-rand': ('pure-rand', vals['PURE_RAND_VERSION'], f\"pure-rand-{vals['PURE_RAND_VERSION']}.tgz\", vals['PURE_RAND_SHA256']),\n    'commander': ('commander', vals['COMMANDER_VERSION'], f\"commander-{vals['COMMANDER_VERSION']}.tgz\", vals['COMMANDER_SHA256']),\n",
    )
    replace_once("tests/node-deps-safety-check.sh", "len(marker['packages'])==5", "len(marker['packages'])==6")
    replace_once("tests/node-deps-safety-check.sh", "len(marker['packages'])==4", "len(marker['packages'])==5")

    replace_once(
        "templates/scripts/selftest.sh",
        'import { xoroshiro128plus } from "pure-rand/generator/xoroshiro128plus";',
        'import { xoroshiro128plus } from "pure-rand/generator/xoroshiro128plus"; import { Command } from "commander";',
    )
    replace_once(
        "templates/scripts/selftest.sh",
        '||typeof xoroshiro128plus!=="function") process.exit(1)',
        '||typeof xoroshiro128plus!=="function"||typeof Command!=="function") process.exit(1)',
    )
    replace_once("templates/scripts/selftest.sh", "len(marker['packages'])==5", "len(marker['packages'])==6")

    replace_once(
        "README.md",
        "- exact offline npm capability capsules for yaml 2.9.0, postgres 3.4.7, PostgreSQL Language Server WASM 0.25.7, fast-check 4.9.0, and pure-rand 8.4.2",
        "- exact offline npm capability capsules for yaml 2.9.0, postgres 3.4.7, PostgreSQL Language Server WASM 0.25.7, fast-check 4.9.0, pure-rand 8.4.2, and commander 15.0.0",
    )
    replace_once(
        "README.md",
        "The target repository's `package-lock.json` remains authority. The capsule set includes `yaml` 2.9.0 for repositories that lock that exact package, alongside the existing database and test-library capsules.",
        "The target repository's `package-lock.json` remains authority. The capsule set includes `yaml` 2.9.0 and `commander` 15.0.0 for repositories that lock those exact packages, alongside the existing database and test-library capsules.",
    )
    replace_once(
        "templates/RUNTIME-README.md",
        "The immutable capsule store currently contains exact bytes for `yaml` 2.9.0, postgres 3.4.7, `@postgres-language-server/wasm` 0.25.7, fast-check 4.9.0 and pure-rand 8.4.2.",
        "The immutable capsule store currently contains exact bytes for `yaml` 2.9.0, postgres 3.4.7, `@postgres-language-server/wasm` 0.25.7, fast-check 4.9.0, pure-rand 8.4.2 and `commander` 15.0.0.",
    )
    replace_once(
        "templates/THIRD-PARTY.md",
        "- pure-rand 8.4.2 — MIT.\n",
        "- pure-rand 8.4.2 — MIT.\n- commander 15.0.0 — MIT.\n",
    )

    license_path = ROOT / "vendor/licenses/THIRD-PARTY-LICENSES.md"
    licenses = license_path.read_text(encoding="utf-8")
    if "\n## commander\n" in licenses:
        raise SystemExit("Commander license already present")
    license_path.write_text(
        licenses.rstrip() + "\n\n## commander\n\n" + license_text.rstrip() + "\n",
        encoding="utf-8",
    )

    (ROOT / ".github/workflows/prepare-commander-capsule.yml").unlink()
    pathlib.Path(__file__).unlink()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
