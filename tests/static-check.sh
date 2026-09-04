#!/usr/bin/env bash
set -euo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
for file in "$ROOT/build.sh" "$ROOT/tests/"*.sh "$ROOT/templates/scripts/"*.sh "$ROOT/templates/bin/agent-env" "$ROOT/scripts/normalize-python-links.sh" "$ROOT/scripts/build-identity.sh" "$ROOT/scripts/build-common.sh" "$ROOT/scripts/rebuild-qualified-database-assets.sh"; do
  bash -n "$file"
done
for file in "$ROOT/templates/bin/python-wrapper" "$ROOT/templates/bin/node-wrapper" "$ROOT/templates/bin/npm-wrapper" "$ROOT/templates/bin/npx-wrapper" "$ROOT/templates/bin/supabase-wrapper" "$ROOT/scripts/uv-isolated-exec.sh"; do
  sh -n "$file"
done
for file in "$ROOT/templates/scripts/"*.py; do python3 -m py_compile "$file"; done
python3 -m py_compile "$ROOT/scripts/normalize-python-sysconfig.py"
python3 -m py_compile "$ROOT/scripts/write-acceptance-metadata.py"
python3 -m py_compile "$ROOT/scripts/check-version-transition.py"
python3 -m py_compile "$ROOT/scripts/check-commit-message.py"
python3 -m py_compile "$ROOT/scripts/check-pr-record.py"
python3 - <<'PY' "$ROOT/versions.env" "$ROOT/requirements.in" "$ROOT/requirements.lock" "$ROOT"
import hashlib, json, pathlib, re, sys
versions_path, req_in_path, lock_path, root = map(pathlib.Path, sys.argv[1:])
versions=versions_path.read_text(encoding='utf-8'); req_in=req_in_path.read_text(encoding='utf-8'); lock=lock_path.read_text(encoding='utf-8')
vals=dict(re.findall(r'^(\w+)="([^"]*)"$', versions, flags=re.M))
for name,value in vals.items():
    if name.endswith('_SHA256'): assert re.fullmatch(r'[0-9a-f]{64}',value),(name,value)
    if name.endswith('_URL'): assert value.startswith('https://'),(name,value)
assert hashlib.sha256(lock_path.read_bytes()).hexdigest()==vals['PYTHON_LOCK_SHA256']
assert '/tmp/' not in lock and '# via' not in lock and 'Build Root' not in lock
packages=re.findall(r'^([A-Za-z0-9_.-]+)==([^ \\n]+)',lock,flags=re.M); locked={n.lower():v for n,v in packages}
for line in req_in.splitlines():
    line=line.strip()
    if not line or line.startswith('#'): continue
    name,version=line.split('==',1); name=re.sub(r'\[.*\]$','',name)
    assert locked.get(name.lower())==version,(name,version,locked.get(name.lower()))
assert 'pytest' not in locked and 'setuptools' not in locked and 'wheel' not in locked
checks={
 'vendor/database/postgresql-client-17.10-linux-x64-gnu.tar.gz':'POSTGRES_CLIENT_SHA256',
 'vendor/database/plpgsql-check-2.8.11-pg17-linux-x64-gnu.tar.gz':'PLPGSQL_CHECK_SHA256'}
for rel,key in checks.items():
    path=root/rel; assert path.is_file(),rel
    assert hashlib.sha256(path.read_bytes()).hexdigest()==vals[key],(rel,key)
manifest_path=root/'vendor/node-capsules/manifest.json'
manifest=json.loads(manifest_path.read_text(encoding='utf-8'))
expected={
    'yaml': ('yaml', vals['YAML_VERSION'], f"yaml-{vals['YAML_VERSION']}.tgz", vals['YAML_SHA256']),
    'postgres': ('node-postgres', vals['POSTGRES_JS_VERSION'], f"postgres-{vals['POSTGRES_JS_VERSION']}.tgz", vals['POSTGRES_JS_SHA256']),
    '@postgres-language-server/wasm': ('pgls-wasm', vals['PGLS_WASM_VERSION'], f"postgres-language-server-wasm-{vals['PGLS_WASM_VERSION']}.tgz", vals['PGLS_WASM_SHA256']),
    'fast-check': ('fast-check', vals['FAST_CHECK_VERSION'], f"fast-check-{vals['FAST_CHECK_VERSION']}.tgz", vals['FAST_CHECK_SHA256']),
    'pure-rand': ('pure-rand', vals['PURE_RAND_VERSION'], f"pure-rand-{vals['PURE_RAND_VERSION']}.tgz", vals['PURE_RAND_SHA256']),
}
assert manifest.get('schema')==1
assert isinstance(manifest.get('packages'),dict) and set(manifest['packages'])==set(expected)
for name,(component,version,file,sha256) in expected.items():
    record=manifest['packages'][name]
    assert record.get('component')==component,(name,'component')
    assert record.get('version')==version,(name,'version')
    assert record.get('file')==file,(name,'file')
    assert record.get('sha256')==sha256,(name,'sha256')
    assert re.fullmatch(r'sha512-[A-Za-z0-9+/]+={0,2}',record.get('integrity','')),(name,'integrity')
    assert str(record.get('url','')).startswith('https://registry.npmjs.org/'),(name,'url')
    assert not (root/'vendor/node-capsules'/file).exists(),(name,'capsule bytes should be acquired, not source-controlled')
pg_package=json.loads((root/'vendor/pg-delta/package.json').read_text(encoding='utf-8'))
pg_lock_path=root/'vendor/pg-delta/package-lock.json'
pg_lock=json.loads(pg_lock_path.read_text(encoding='utf-8'))
assert hashlib.sha256(pg_lock_path.read_bytes()).hexdigest()==vals['PG_DELTA_LOCK_SHA256']
assert pg_package.get('private') is True
assert pg_package.get('dependencies')=={'@supabase/pg-delta':vals['PG_DELTA_VERSION']}
assert pg_lock.get('lockfileVersion')==3
pg_packages=pg_lock.get('packages'); assert isinstance(pg_packages,dict) and pg_packages
assert pg_packages[''].get('dependencies')=={'@supabase/pg-delta':vals['PG_DELTA_VERSION']}
direct=pg_packages.get('node_modules/@supabase/pg-delta',{})
assert direct.get('version')==vals['PG_DELTA_VERSION']
assert direct.get('license')=='MIT'
assert direct.get('bin')=={'pgdelta':'dist/cli/bin/cli.js'}
for path,record in pg_packages.items():
    if not path.startswith('node_modules/'): continue
    assert record.get('version'),(path,'version')
    assert re.fullmatch(r'sha512-[A-Za-z0-9+/]+={0,2}',record.get('integrity','')),(path,'integrity')
    assert str(record.get('resolved','')).startswith('https://registry.npmjs.org/'),(path,'resolved')
    assert record.get('license'),(path,'license')
print('hash-lock-and-vendor-shapes-ok')
PY
rm -rf "$ROOT/templates/scripts/__pycache__" "$ROOT/scripts/__pycache__"
for file in requirements.lock payload/AGENTS.md.in templates/RUNTIME-README.md templates/scripts/github.sh templates/scripts/git-handoff.py templates/scripts/doctor.py templates/scripts/postgres.py templates/scripts/postgrest.py templates/scripts/pgtap.py templates/scripts/node-deps.py templates/scripts/capabilities.py templates/bin/agent-env scripts/build-identity.sh scripts/build-common.sh scripts/check-version-transition.py scripts/check-commit-message.py scripts/check-pr-record.py scripts/uv-isolated-exec.sh scripts/write-acceptance-metadata.py scripts/rebuild-qualified-database-assets.sh vendor/licenses/THIRD-PARTY-LICENSES.md vendor/node-capsules/manifest.json vendor/pg-delta/package.json vendor/pg-delta/package-lock.json vendor/pg-delta/LICENSE vendor/postgrest/LICENSE vendor/supabase/LICENSE templates/bin/supabase-wrapper templates/scripts/pg-delta.mjs .github/pull_request_template.md tests/build-identity-check.sh tests/version-transition-check.sh tests/pr-record-check.sh tests/node-deps-safety-check.sh tests/git-handoff-check.sh; do
  [[ -s "$ROOT/$file" ]] || { echo "Required runtime/build source missing: $file" >&2; exit 1; }
done
# The shipped router is a routing surface; do not enforce an arbitrary byte budget in place of semantic review.
[[ ! -e "$ROOT/payload/AGENTS.md" && ! -e "$ROOT/templates/AGENTS.md" ]] || {
  echo "Shipped agent instructions must use the non-discoverable payload/AGENTS.md.in source name inside the builder repository." >&2
  exit 1
}
# Authentication must remain host/session state, not redirected into the portable payload.
if grep -R -nE 'export[[:space:]]+GH_CONFIG_DIR=|GH_CONFIG_DIR=' "$ROOT/templates"; then
  echo "Do not redirect GitHub credential storage into the portable bundle." >&2
  exit 1
fi
# Ad-hoc package/runtime installation belongs in mutable state rather than verified payload directories.
grep -F 'UV_PYTHON_INSTALL_DIR="$ERPI_AGENT_ENV/state/uv-python"' "$ROOT/templates/activate" >/dev/null
grep -F 'NPM_CONFIG_PREFIX="$ERPI_AGENT_ENV/state/npm-global"' "$ROOT/templates/activate" >/dev/null
# Current first-party authority must not regress to the retired product identity.
# Build the token rather than embedding it so the guard does not match itself.
legacy_brand="$(printf '%s%s' 'mag' 'net')"
if grep -R -nFi --binary-files=without-match "$legacy_brand" \
  "$ROOT/AGENTS.md" "$ROOT/README.md" "$ROOT/CONTRIBUTING.md" "$ROOT/VALIDATION.md" \
  "$ROOT/build.sh" "$ROOT/versions.env" "$ROOT/.github" "$ROOT/payload" \
  "$ROOT/scripts" "$ROOT/templates" "$ROOT/tests" "$ROOT/vendor/pg-delta"; then
  echo "Retired product identity remains in current first-party source." >&2
  exit 1
fi
# Mutable state is outside immutable payload verification/topology and is pristine in the distributed archive.
grep -F "! -path './state/*'" "$ROOT/templates/scripts/verify.sh" >/dev/null
grep -F '! -path "$ROOT/state/*"' "$ROOT/templates/scripts/selftest.sh" >/dev/null
grep -F 'log "Reset mutable state for distribution"' "$ROOT/build.sh" >/dev/null
grep -F 'reset_runtime_state' "$ROOT/build.sh" >/dev/null
grep -F 'Mutable state was not pristine before packaging:' "$ROOT/build.sh" >/dev/null
# No shipped shell path may use an early-closing `head` pipeline under `set -o pipefail`.
if grep -R -nE '\|[[:space:]]*head([[:space:]]|$)' "$ROOT/build.sh" "$ROOT/templates" "$ROOT/tests" "$ROOT/scripts"; then
  echo "Avoid early-closing head pipelines under pipefail; capture output or consume it fully." >&2
  exit 1
fi
grep -F 'getconf GNU_LIBC_VERSION' "$ROOT/build.sh" >/dev/null
grep -F 'MIN_KERNEL_VERSION="4.18"' "$ROOT/versions.env" >/dev/null
grep -F 'MIN_GLIBC_VERSION="2.28"' "$ROOT/versions.env" >/dev/null
grep -F 'MIN_GLIBCXX_SYMBOL="GLIBCXX_3.4.25"' "$ROOT/versions.env" >/dev/null
# yq is verified directly against the immutable GitHub release-asset digest; do not parse rhash columns.
grep -F 'YQ_SHA256="fa52a4e758c63d38299163fbdd1edfb4c4963247918bf9c1c5d31d84789eded4"' "$ROOT/versions.env" >/dev/null
! grep -R -nE 'YQ_CHECKSUMS_SHA256|YQ_HASH|yq-checksums|awk.*yq_linux_amd64' "$ROOT/build.sh" "$ROOT/versions.env"
grep -F "find . -xtype l ! -path './state/*'" "$ROOT/templates/scripts/verify.sh" >/dev/null
# Standalone PostgREST is an exact upstream static asset with bounded local routing.
grep -F 'POSTGREST_VERSION="14.16"' "$ROOT/versions.env" >/dev/null
grep -F 'POSTGREST_SHA256="36b8ae140f188cfcd6003494805bf35a41e895f88c12be9183d60f91782145c6"' "$ROOT/versions.env" >/dev/null
grep -F 'POSTGREST_SUPABASE_CLI_BASELINE="2.114.0"' "$ROOT/versions.env" >/dev/null
grep -F 'postgrest-v${POSTGREST_VERSION}-linux-static-x86-64.tar.xz' "$ROOT/build.sh" >/dev/null
grep -F 'build_acquire_verified "$POSTGREST_URL" "$POSTGREST_AR" "$POSTGREST_SHA256"' "$ROOT/build.sh" >/dev/null
grep -F 'PGRST_SERVER_HOST' "$ROOT/templates/scripts/postgrest.py" >/dev/null
grep -F 'RETARGET_QUERY_KEYS' "$ROOT/templates/scripts/postgrest.py" >/dev/null
grep -F 'postgrest run' "$ROOT/templates/bin/agent-env" >/dev/null
# Supabase CLI is the exact official paired Linux amd64 release and keeps credentials outside the bundle.
grep -F 'SUPABASE_CLI_VERSION="2.114.0"' "$ROOT/versions.env" >/dev/null
grep -F 'SUPABASE_CLI_SHA256="f36a33ca867f1cce9ba5efa705863fdc545d1465d3719a721793ea67eb692c5a"' "$ROOT/versions.env" >/dev/null
grep -F 'supabase_${SUPABASE_CLI_VERSION}_linux_amd64.tar.gz' "$ROOT/build.sh" >/dev/null
grep -F 'SUPABASE_GO_BINARY="$ROOT/runtime/supabase/supabase-go"' "$ROOT/templates/bin/supabase-wrapper" >/dev/null
grep -F 'source_row supabase-cli' "$ROOT/build.sh" >/dev/null
grep -F 'SUPABASE_MAX_GLIBC=' "$ROOT/build.sh" >/dev/null
grep -F "'supabase':probe(ROOT/'bin/supabase',['--version'])" "$ROOT/templates/scripts/doctor.py" >/dev/null
grep -F 'SUPABASE_TELEMETRY_DISABLED=1 supabase migration new runtime_probe </dev/null' "$ROOT/templates/scripts/selftest.sh" >/dev/null
! grep -R -nE 'SUPABASE_ACCESS_TOKEN=|SUPABASE_DB_PASSWORD=|XDG_CONFIG_HOME=.*ERPI_AGENT_ENV|HOME=.*ERPI_AGENT_ENV' "$ROOT/templates/bin/supabase-wrapper" "$ROOT/templates/activate"
# The v1 Python lock is source-controlled input, not resolved during hydration.
grep -F 'build_verify_sha256 "$SELF_DIR/requirements.lock" "$PYTHON_LOCK_SHA256"' "$ROOT/build.sh" >/dev/null
! grep -F 'pip compile' "$ROOT/build.sh"
# Pip bootstrap code is verified before execution.
grep -F 'build_verify_sha256 "$PIP_BOOT_WHEEL" "$PIP_BOOTSTRAP_WHEEL_SHA256"' "$ROOT/build.sh" >/dev/null
grep -F 'PIP_BOOT_CACHE="$DL/pip-26.1.2-py3-none-any.whl"' "$ROOT/build.sh" >/dev/null
# uv build/recovery operations are isolated from project/user selection overrides without suppressing proxy/CA settings.
grep -F 'UV_NO_CONFIG=1' "$ROOT/scripts/uv-isolated-exec.sh" >/dev/null
grep -F 'unset UV_PYTHON_DOWNLOADS_JSON_URL' "$ROOT/scripts/uv-isolated-exec.sh" >/dev/null
# Build-time caches live beside direct-download cache, not in the disposable payload tree.
grep -F 'BUILDER_UV_PYTHON_CACHE="$CACHE_DIR/uv-python-archives"' "$ROOT/build.sh" >/dev/null
grep -F 'UV_PYTHON_CACHE_DIR="$BUILDER_UV_PYTHON_CACHE"' "$ROOT/build.sh" >/dev/null
grep -F 'PIP_CACHE_DIR="$BUILDER_PIP_CACHE"' "$ROOT/build.sh" >/dev/null
# uv-managed absolute convenience links are preserved semantically but made relative.
grep -F 'normalize-python-links.sh" "$BUILD/runtime/python"' "$ROOT/build.sh" >/dev/null
# uv-managed Python sysconfig is normalized into a location-neutral, immutable file.
grep -F '__ERPI_AGENT_PYTHON_PREFIX__' "$ROOT/scripts/normalize-python-sysconfig.py" >/dev/null
grep -F "sysconfig.get_config_var('BINDIR')" "$ROOT/templates/scripts/selftest.sh" >/dev/null
# Native/compiled Python and uv-generated console entrypoints are exercised after each relocation/rebuild.
grep -F 'import httpx, jsonschema, packaging, yaml, tomlkit, rpds' "$ROOT/templates/scripts/selftest.sh" >/dev/null
grep -F 'from yaml import CLoader' "$ROOT/templates/scripts/selftest.sh" >/dev/null
! grep -F 'pytest --version' "$ROOT/templates/scripts/selftest.sh"
grep -Fx 'pip --version >/dev/null' "$ROOT/templates/scripts/selftest.sh" >/dev/null
# Offline rebuilds must canonicalize uv's timestamp-bearing installer metadata before integrity verification.
grep -F "cache=dist/'uv_cache.json'" "$ROOT/templates/scripts/selftest.sh" >/dev/null
grep -F "cache_record=f'{dist.name}/uv_cache.json'" "$ROOT/templates/scripts/selftest.sh" >/dev/null
grep -F "csv.writer(h,lineterminator='\\n').writerows(kept)" "$ROOT/templates/scripts/selftest.sh" >/dev/null
selftest_line="$(grep -nF '"$ROOT/scripts/selftest.sh"' "$ROOT/templates/scripts/rebuild-python.sh" | cut -d: -f1)"
verify_line="$(grep -nF '"$ROOT/scripts/verify.sh"' "$ROOT/templates/scripts/rebuild-python.sh" | cut -d: -f1)"
[[ -n "$selftest_line" && -n "$verify_line" && "$selftest_line" -lt "$verify_line" ]] || {
  echo "Offline rebuild must canonicalize through selftest before immutable verification." >&2
  exit 1
}
# pyvenv.cfg is the sole relocation-mutable venv file: preserve uv metadata and patch only `home`.
grep -F -- "--exclude='pyvenv.cfg' \"\$ORIGINAL_BUILD_ROOT\"" "$ROOT/build.sh" >/dev/null
! grep -F 'executable = $PYROOT_LINK' "$ROOT/templates/scripts/repair-python.sh"
grep -F 'Fresh extraction retained its archive-build location' "$ROOT/build.sh" >/dev/null
# GitHub OAuth must not persist a relocatable gh path into host-global Git config.
grep -F 'GH_PROMPT_DISABLED=1 gh auth login --hostname "$HOST" --git-protocol https --web' "$ROOT/templates/scripts/github.sh" >/dev/null
grep -F "git config --local --add credential.https://github.com.helper '!gh auth git-credential'" "$ROOT/templates/scripts/github.sh" >/dev/null
grep -F 'git push --dry-run --no-verify' "$ROOT/templates/scripts/github.sh" >/dev/null
grep -F 'github-git' "$ROOT/templates/bin/agent-env" >/dev/null
grep -F 'github-git' "$ROOT/payload/AGENTS.md.in" >/dev/null
grep -F 'git-handoff restore' "$ROOT/templates/bin/agent-env" >/dev/null
grep -F 'git-handoff restore' "$ROOT/payload/AGENTS.md.in" >/dev/null
grep -F 'git-bundle-zip-v1' "$ROOT/build.sh" >/dev/null
grep -F 'GIT_CONFIG_NOSYSTEM' "$ROOT/templates/scripts/git-handoff.py" >/dev/null
grep -F 'GIT_CONFIG_GLOBAL' "$ROOT/templates/scripts/git-handoff.py" >/dev/null
grep -F 'bundle", "verify"' "$ROOT/templates/scripts/git-handoff.py" >/dev/null
grep -F 'https://github.com/{repository}.git' "$ROOT/templates/scripts/git-handoff.py" >/dev/null
grep -F 'cp "$SELF_DIR/templates/scripts/git-handoff.py" "$BUILD/scripts/git-handoff.py"' "$ROOT/build.sh" >/dev/null
if grep -R -nF 'gh auth setup-git' "$ROOT/templates/scripts" "$ROOT/templates/bin"; then
  echo "Do not persist the portable gh path with gh auth setup-git." >&2
  exit 1
fi
if grep -R -nE 'git[[:space:]]+config[[:space:]]+--global.*credential' "$ROOT/templates/scripts" "$ROOT/templates/bin"; then
  echo "Do not write Git credential helpers globally from the portable bundle." >&2
  exit 1
fi
python3 - <<'PY_VERSION' "$ROOT/versions.env"
import re,sys
text=open(sys.argv[1],encoding='utf-8').read()
matches=re.findall(r'^PRODUCT_VERSION="([^"]+)"$',text,re.M)
assert len(matches)==1,matches
version=matches[0]
assert re.fullmatch(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-(?:alpha|beta|rc)\.[1-9][0-9]*(?:-[1-9][0-9]*)?)?',version),version
assert '+g' not in version and not version.endswith('-dev'),version
assert 'BUNDLE_VERSION=' not in text
PY_VERSION
grep -F 'BUILD_CUTOFF="2026-08-20T04:30:00Z"' "$ROOT/versions.env" >/dev/null
grep -F 'ARCHIVE_MTIME="2026-08-20T04:30:00Z"' "$ROOT/versions.env" >/dev/null
grep -F 'SHELLCHECK_SOURCE_SHA256="8b07554f92e4fbfc33f1539a1f475f21c6503ceae8f806efcc518b1f529f7102"' "$ROOT/versions.env" >/dev/null
grep -F 'PYTHON_DISTRIBUTION_BUILD="20260805"' "$ROOT/versions.env" >/dev/null
grep -F 'PYTHON_DISTRIBUTION_SHA256="39e82d05926bdcd206732026bcd878d9f00e288cd227d91c1fabf379b6ea4fa5"' "$ROOT/versions.env" >/dev/null
grep -F 'cpython-3.13.14%2B20260805-x86_64-unknown-linux-gnu-install_only_stripped.tar.gz' "$ROOT/versions.env" >/dev/null
grep -F 'Managed Python build provenance does not match pinned build' "$ROOT/build.sh" >/dev/null
grep -F '"python_provenance"' "$ROOT/build.sh" >/dev/null
grep -F 'source_row python-build-standalone' "$ROOT/build.sh" >/dev/null
grep -F "delimiter='\t'" "$ROOT/build.sh" >/dev/null
! grep -F 'component\tversion\turl\tsha256' "$ROOT/build.sh"
grep -F 'vendor/licenses/THIRD-PARTY-LICENSES.md' "$ROOT/build.sh" >/dev/null
grep -F 'licenses/third-party/THIRD-PARTY-LICENSES.md' "$ROOT/build.sh" >/dev/null
grep -F '@PRODUCT_VERSION@' "$ROOT/templates/RUNTIME-README.md" >/dev/null
grep -F '@SOURCE_DESCRIPTION@' "$ROOT/templates/RUNTIME-README.md" >/dev/null
grep -F '@SOURCE_COMMIT@' "$ROOT/templates/RUNTIME-README.md" >/dev/null
grep -F 'shellcheck-v${SHELLCHECK_VERSION}-source.tar.gz' "$ROOT/build.sh" >/dev/null
grep -F 'SHELLCHECK_SOURCE_SHA256' "$ROOT/build.sh" >/dev/null
grep -F '__ERPI_AGENT_RELOCATE__/runtime/python/current/bin' "$ROOT/build.sh" >/dev/null
grep -F -- '--sort=name --format=gnu --numeric-owner --owner=0 --group=0' "$ROOT/build.sh" >/dev/null
grep -F 'gzip -n > "$dest"' "$ROOT/build.sh" >/dev/null
grep -F 'Archive packaging is not deterministic for the accepted payload.' "$ROOT/build.sh" >/dev/null
grep -F 'Immutable payload contains a group/world-writable regular file' "$ROOT/build.sh" >/dev/null
grep -F 'args+=(--prerelease)' "$ROOT/.github/workflows/publish-release.yml" >/dev/null
# Product version and Git source-ancestry policy.
! grep -q '^  pull_request:' "$ROOT/.github/workflows/accept-runtime.yml"
grep -q '^  push:' "$ROOT/.github/workflows/accept-runtime.yml"
grep -q '^  workflow_dispatch:' "$ROOT/.github/workflows/accept-runtime.yml"
grep -F '## Product version and source identity' "$ROOT/CONTRIBUTING.md" >/dev/null
grep -F '## Source identity and release lifecycle' "$ROOT/CONTRIBUTING.md" >/dev/null
grep -F '## Source identity and release boundary' "$ROOT/VALIDATION.md" >/dev/null
grep -F 'source "$SELF_DIR/scripts/build-identity.sh"' "$ROOT/build.sh" >/dev/null
grep -F 'ERPI_AGENT_SOURCE_COMMIT' "$ROOT/build.sh" >/dev/null
grep -F 'ERPI_AGENT_SOURCE_BASE_TAG' "$ROOT/build.sh" >/dev/null
grep -F 'ERPI_AGENT_SOURCE_DISTANCE' "$ROOT/build.sh" >/dev/null
grep -F 'ERPI_AGENT_SOURCE_DESCRIPTION' "$ROOT/build.sh" >/dev/null
grep -F "describe --tags --match 'v[0-9]*' --abbrev=0 --first-parent" "$ROOT/build.sh" >/dev/null
grep -F 'Distributable builds require a clean committed source tree' "$ROOT/build.sh" >/dev/null
grep -F 'ARTIFACT="$OUT_DIR/${ARTIFACT_STEM}.tar.gz"' "$ROOT/build.sh" >/dev/null
grep -F '"product_version": "$PRODUCT_VERSION"' "$ROOT/build.sh" >/dev/null
grep -F '"source": {"commit": "$SOURCE_COMMIT", "description": "$SOURCE_DESCRIPTION", "base_tag": "$SOURCE_BASE_TAG", "distance": $SOURCE_DISTANCE}' "$ROOT/build.sh" >/dev/null
grep -F 'expected_filename = f"{artifact_stem}.tar.gz"' "$ROOT/scripts/write-acceptance-metadata.py" >/dev/null
grep -F "source_description == f'{source_base_tag}-{source_distance}-g{source_commit[:12]}'" "$ROOT/templates/scripts/selftest.sh" >/dev/null
grep -F 'POSTGRES_VERSION="17.10"' "$ROOT/versions.env" >/dev/null
grep -F 'POSTGRES_SOURCE_URL="https://ftp.postgresql.org/pub/source/v17.10/postgresql-17.10.tar.bz2"' "$ROOT/versions.env" >/dev/null
grep -F 'POSTGRES_SOURCE_SHA256="078a03516dcdbdb705fecaf415ea3d13a956c589e46f09fed68a06fb00598c90"' "$ROOT/versions.env" >/dev/null
grep -F 'POSTGRES_BUILD_IMAGE="quay.io/pypa/manylinux_2_28_x86_64"' "$ROOT/versions.env" >/dev/null
grep -F 'POSTGRES_BUILD_IMAGE_SHA256="0c87ccb5996dab6c3b7612ee4fda7b80c4ab3c44a86c2541e4a872afdf4f131b"' "$ROOT/versions.env" >/dev/null
grep -F 'POSTGRES_FLEX_VERSION="2.6.1"' "$ROOT/versions.env" >/dev/null
grep -F 'POSTGRES_FLEX_RPM_NEVRA="flex-2.6.1-9.el8.x86_64"' "$ROOT/versions.env" >/dev/null
grep -F 'POSTGRES_FLEX_RPM_URL="https://repo.almalinux.org/almalinux/8.10/AppStream/x86_64/os/Packages/flex-2.6.1-9.el8.x86_64.rpm"' "$ROOT/versions.env" >/dev/null
grep -F 'POSTGRES_FLEX_RPM_SHA256="5da3a77e64e6692695e93f67774faec62c782bb5ad9595ede924110c3fc44a21"' "$ROOT/versions.env" >/dev/null
if grep -R -nE 'dnf[[:space:]].*install|yum[[:space:]].*install' "$ROOT/build.sh" "$ROOT/scripts/rebuild-qualified-database-assets.sh"; then
  echo "Pinned PostgreSQL builds must not resolve build packages from live package repositories." >&2
  exit 1
fi
grep -F -- 'docker run --rm --network none' "$ROOT/build.sh" >/dev/null
grep -F -- 'docker run --rm --network none' "$ROOT/scripts/rebuild-qualified-database-assets.sh" >/dev/null
grep -F 'rpm -Uvh --nodeps --noscripts /work/postgres-flex.rpm' "$ROOT/build.sh" >/dev/null
grep -F 'rpm -Uvh --nodeps --noscripts /work/postgres-flex.rpm' "$ROOT/scripts/rebuild-qualified-database-assets.sh" >/dev/null
grep -F 'make AROPT=crsD -j2' "$ROOT/build.sh" >/dev/null
grep -F 'make AROPT=crsD -j2' "$ROOT/scripts/rebuild-qualified-database-assets.sh" >/dev/null
grep -F 'source_row postgres-server-build-flex' "$ROOT/build.sh" >/dev/null
grep -F "'postgres-server-build-flex'" "$ROOT/templates/scripts/selftest.sh" >/dev/null
for workflow in "$ROOT/.github/workflows/accept-runtime.yml" "$ROOT/.github/workflows/build-dist.yml"; do
  grep -F 'name: Compute builder download cache key' "$workflow" >/dev/null
  grep -F 'key: erpi-agent-env-linux-x64-${{ steps.download-cache.outputs.key }}' "$workflow" >/dev/null
  ! grep -F "hashFiles('versions.env'" "$workflow" >/dev/null
done
[[ ! -e "$ROOT/vendor/database/postgres-server-17.10-linux-x64.txz" ]] || { echo 'Opaque prebuilt PostgreSQL server must not return.' >&2; exit 1; }
[[ ! -e "$ROOT/scripts/qualify-postgres-server.sh" ]] || { echo 'Temporary PostgreSQL qualification script must not remain in the live tree.' >&2; exit 1; }
! grep -F 'qualify-postgres-server' "$ROOT/.github/workflows/build-dist.yml"
grep -F 'POSTGRES_BUILD_IMAGE_REF="$(build_docker_image_ref "$POSTGRES_BUILD_IMAGE" "$POSTGRES_BUILD_IMAGE_SHA256")"' "$ROOT/build.sh" >/dev/null
grep -F './configure --prefix=/usr/local/pg-build --without-readline --without-zlib --without-icu' "$ROOT/build.sh" >/dev/null
grep -F 'cp -a "$PG_BUILD_WORK/stage/usr/local/pg-build/." "$BUILD/runtime/postgres/server/"' "$ROOT/build.sh" >/dev/null
grep -F 'Source-built PostgreSQL server unexpectedly contains a bundled third-party shared library.' "$ROOT/build.sh" >/dev/null
grep -F 'Source-built PostgreSQL exceeds runtime GLIBC floor' "$ROOT/build.sh" >/dev/null
grep -F 'PG_RUNTIME_LD_LIBRARY_PATH="$BUILD/runtime/postgres/client/lib:$BUILD/runtime/postgres/server/lib"' "$ROOT/build.sh" >/dev/null
grep -F 'LD_LIBRARY_PATH="$PG_RUNTIME_LD_LIBRARY_PATH" ldd "$f"' "$ROOT/build.sh" >/dev/null
grep -F 'runtime_libs = [str(CLIENT / "lib"), str(SERVER / "lib")]' "$ROOT/templates/scripts/postgres.py" >/dev/null
grep -F 'env["LD_LIBRARY_PATH"] = ":".join(runtime_libs)' "$ROOT/templates/scripts/postgres.py" >/dev/null
grep -F 'source_row postgres-server-source' "$ROOT/build.sh" >/dev/null
grep -F 'source_row postgres-server-build-image' "$ROOT/build.sh" >/dev/null
grep -F "probe_env['NO_PROXY']='127.0.0.1,localhost'" "$ROOT/templates/scripts/selftest.sh" >/dev/null
grep -F "dead_proxy='http://127.0.0.1:9'" "$ROOT/templates/scripts/selftest.sh" >/dev/null
grep -F 'agent-env postgres run' "$ROOT/templates/RUNTIME-README.md" >/dev/null
grep -F 'agent-env node-deps hydrate' "$ROOT/templates/RUNTIME-README.md" >/dev/null
grep -F 'Do not fragment a suite merely to satisfy an agent wrapper timeout.' "$ROOT/payload/AGENTS.md.in" >/dev/null
grep -F 'Unsupported bundled PostgreSQL client tool' "$ROOT/templates/bin/agent-env" >/dev/null
grep -F 'DATABASE_URL' "$ROOT/templates/scripts/postgres.py" >/dev/null
grep -F '127.0.0.1' "$ROOT/templates/scripts/postgres.py" >/dev/null
grep -F 'pg_checksums' "$ROOT/templates/scripts/postgres.py" >/dev/null
grep -F "unix_socket_directories = ''" "$ROOT/templates/scripts/postgres.py" >/dev/null
grep -F -- '--- PostgreSQL startup log ---' "$ROOT/templates/scripts/postgres.py" >/dev/null
! grep -F 'cluster / "socket"' "$ROOT/templates/scripts/postgres.py" >/dev/null
grep -F 'package-lock.json is required' "$ROOT/templates/scripts/node-deps.py" >/dev/null
! grep -R -nE 'anon|authenticated|service_role' "$ROOT/templates/scripts/postgres.py" "$ROOT/templates/scripts/pgtap.py" "$ROOT/templates/scripts/node-deps.py"
# Repository-locked Node dependencies are immutable offline runtime capsules, acquired by the connected builder.
grep -F 'YAML_VERSION="2.9.0"' "$ROOT/versions.env" >/dev/null
grep -F 'YAML_SHA256="008fa204cb1ba700e0272ba045abbf09a6ffe63456e8146ba97cac6c2ad1ef91"' "$ROOT/versions.env" >/dev/null
grep -F '"component": "yaml"' "$ROOT/vendor/node-capsules/manifest.json" >/dev/null
grep -F '"url": "https://registry.npmjs.org/yaml/-/yaml-2.9.0.tgz"' "$ROOT/vendor/node-capsules/manifest.json" >/dev/null
grep -F 'build_acquire_verified "$url" "$capsule" "$hash"' "$ROOT/build.sh" >/dev/null
grep -F 'source_row "$component" "$version" "$url" "$hash"' "$ROOT/build.sh" >/dev/null
! find "$ROOT/vendor/node-capsules" -maxdepth 1 -type f -name '*.tgz' -print -quit | grep -q .
! grep -R -nF 'runtime/node/lib/node_modules/yaml' "$ROOT/build.sh" "$ROOT/templates" "$ROOT/README.md" "$ROOT/VALIDATION.md"
! grep -R -nF 'NODE_PATH=' "$ROOT/templates/activate" "$ROOT/templates/bin/node-wrapper" "$ROOT/templates/bin/agent-env"
# pg-delta is runtime-owned, exactly locked, plan-only, and restricted to numeric loopback.
grep -F 'PG_DELTA_VERSION="1.0.0-alpha.33"' "$ROOT/versions.env" >/dev/null
grep -F 'PG_DELTA_LOCK_SHA256="fa6659239ce4e70738b5936f5690c2fdcf6bf2ef09e7c13a58c0009c8401bccf"' "$ROOT/versions.env" >/dev/null
grep -F 'PG_DELTA_SUPABASE_CLI_BASELINE="2.114.0"' "$ROOT/versions.env" >/dev/null
grep -F 'build_verify_sha256 "$PG_DELTA_LOCK" "$PG_DELTA_LOCK_SHA256"' "$ROOT/build.sh" >/dev/null
grep -F 'build_connected_npm "$BUILD/bin/npm" ci --prefix "$BUILD/runtime/pg-delta" --ignore-scripts --no-audit --no-fund' "$ROOT/build.sh" >/dev/null
grep -F 'rm -rf "$BUILD/runtime/pg-delta/node_modules/.bin"' "$ROOT/build.sh" >/dev/null
grep -F 'source_row pg-delta-lock' "$ROOT/build.sh" >/dev/null
grep -F 'pg-delta-package-lock.json' "$ROOT/scripts/download-cache-key.sh" >/dev/null
grep -F 'pg-delta plan [...]' "$ROOT/templates/bin/agent-env" >/dev/null
grep -F 'numeric loopback only' "$ROOT/templates/scripts/pg-delta.mjs" >/dev/null
grep -F 'skipDefaultPrivilegeSubtraction: true' "$ROOT/templates/scripts/pg-delta.mjs" >/dev/null
grep -F 'includeTransactions: false' "$ROOT/templates/scripts/pg-delta.mjs" >/dev/null
grep -F 'remote database URLs are refused' "$ROOT/templates/scripts/pg-delta.mjs" >/dev/null
grep -F 'pgdelta-convergence/envelope.json' "$ROOT/templates/scripts/selftest.sh" >/dev/null
grep -F '198.51.100.10' "$ROOT/templates/scripts/selftest.sh" >/dev/null
grep -F 'auth.managed_noise' "$ROOT/templates/scripts/selftest.sh" >/dev/null
! grep -E '^[[:space:]]*(apply|sync)\)' "$ROOT/templates/bin/agent-env"
[[ ! -e "$ROOT/.github/workflows/tmp-pg-delta-qualification.yml" ]] || { echo 'Temporary pg-delta qualification workflow must not remain after promotion.' >&2; exit 1; }
[[ ! -e "$ROOT/.github/workflows/tmp-export-source.yml" ]] || { echo 'Temporary source-export workflow must not remain after promotion.' >&2; exit 1; }
# Connected acquisition is centralized: direct artifacts use one verified cache path, while lock-driven resolvers only neutralize accidental offline-only selection.
grep -F 'source "$SELF_DIR/scripts/build-common.sh"' "$ROOT/build.sh" >/dev/null
grep -F 'source "$SELF_DIR/scripts/build-common.sh"' "$ROOT/scripts/rebuild-qualified-database-assets.sh" >/dev/null
grep -F 'build_acquire_verified "$PYTHON_DISTRIBUTION_URL" "$PYTHON_AR" "$PYTHON_DISTRIBUTION_SHA256"' "$ROOT/build.sh" >/dev/null
grep -F -- '--mirror "file://$PYTHON_MIRROR_ROOT"' "$ROOT/build.sh" >/dev/null
grep -F 'build_connected_pip "$BUILD/env/bin/python" -m pip download' "$ROOT/build.sh" >/dev/null
grep -F 'build_connected_npm "$BUILD/bin/npm" ci' "$ROOT/build.sh" >/dev/null
[[ "$(grep -R -l 'curl --fail --location' "$ROOT/build.sh" "$ROOT/scripts" --include='*.sh' | wc -l)" == 1 ]] || { echo 'Direct download implementation must live only in scripts/build-common.sh.' >&2; exit 1; }
grep -F 'PLPGSQL_CHECK_SOURCE_URL=' "$ROOT/versions.env" >/dev/null
grep -F 'build_acquire_verified "$PLPGSQL_CHECK_SOURCE_URL"' "$ROOT/scripts/rebuild-qualified-database-assets.sh" >/dev/null
"$ROOT/tests/build-common-check.sh"
# Candidate boundaries are enforced both structurally and by executable regression tests.
require_contains() {
  local needle="$1" file="$2" label="$3"
  grep -F -- "$needle" "$file" >/dev/null || { echo "Missing candidate invariant: $label ($file)" >&2; exit 1; }
}
require_contains 'NODE_CAPSULE_MANIFEST="$SELF_DIR/vendor/node-capsules/manifest.json"' "$ROOT/build.sh" 'source-controlled Node capsule manifest'
require_contains 'install -m 0644 "$NODE_CAPSULE_MANIFEST" "$BUILD/manifest/node-capsules.json"' "$ROOT/build.sh" 'runtime manifest copy'
require_contains 'MARKER_SCHEMA = 2' "$ROOT/templates/scripts/node-deps.py" 'content-bound ownership marker schema'
require_contains 'def package_tree_sha256' "$ROOT/templates/scripts/node-deps.py" 'package tree fingerprinting'
require_contains 'ensure_directory_path(dest.parent, repo, label=f"parent path for {name}")' "$ROOT/templates/scripts/node-deps.py" 'scoped package parent containment'
require_contains 'package destination changed during hydration; refusing partial commit' "$ROOT/templates/scripts/node-deps.py" 'transactional hydration recheck'
require_contains 'owned package contents changed; refusing to continue' "$ROOT/templates/scripts/node-deps.py" 'content-bound cleanup ownership'
require_contains 'unsupported ownership marker schema; refusing unsafe legacy/stale marker' "$ROOT/templates/scripts/node-deps.py" 'legacy marker refusal'
require_contains 'node-deps --repo "$NODE_FIXTURE" hydrate' "$ROOT/templates/scripts/selftest.sh" 'real offline Node hydration'
require_contains "marker['schema']==2" "$ROOT/templates/scripts/selftest.sh" 'runtime ownership marker validation'
require_contains 'pg-delta accepted a remote database URL.' "$ROOT/templates/scripts/selftest.sh" 'pg-delta remote-target refusal'
require_contains 'pgdelta-convergence/envelope.json' "$ROOT/templates/scripts/selftest.sh" 'pg-delta convergence proof'
require_contains 'pgTAP negative probe unexpectedly passed' "$ROOT/templates/scripts/selftest.sh" 'pgTAP negative proof'
require_contains 'pg_amcheck --install-missing --database=postgres' "$ROOT/templates/scripts/selftest.sh" 'pg_amcheck proof'
require_contains 'pgbench -c 2 -j 1 -t 2 postgres' "$ROOT/templates/scripts/selftest.sh" 'pgbench concurrency proof'
require_contains "bash -c 'exit 23'" "$ROOT/templates/scripts/selftest.sh" 'child exit propagation proof'
require_contains 'kill -TERM "$runner_pid"' "$ROOT/templates/scripts/selftest.sh" 'signal teardown proof'
require_contains 'for (( attempt=0; attempt<100; attempt++ )); do' "$ROOT/templates/scripts/selftest.sh" 'dependency-free signal readiness loop'
"$ROOT/tests/build-identity-check.sh"
"$ROOT/tests/version-transition-check.sh"
"$ROOT/tests/pr-record-check.sh"
"$ROOT/tests/github-auth-check.sh"
"$ROOT/tests/acceptance-metadata-check.sh"
"$ROOT/tests/uv-isolation-check.sh"
"$ROOT/tests/repair-python-check.sh"
"$ROOT/tests/python-link-relocation-check.sh"
"$ROOT/tests/sysconfig-relocation-check.sh"
"$ROOT/tests/node-deps-safety-check.sh"
"$ROOT/tests/git-handoff-check.sh"
node_acquire_count="$(grep -Fc 'build_acquire_verified "$NODE_URL" "$NODE_AR" "$NODE_SHA256"' "$ROOT/build.sh")"
[[ "$node_acquire_count" == 1 ]] || { echo "Expected exactly one shared Node acquisition call, found $node_acquire_count" >&2; exit 1; }
if grep -F 'registry.npmjs.org/yaml' "$ROOT/build.sh" >/dev/null; then
  echo 'yaml source URL belongs in the capsule manifest, not bespoke build logic.' >&2
  exit 1
fi
echo "Builder static checks passed."
