#!/usr/bin/env bash
set -euo pipefail
SELF_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck disable=SC1091
source "$SELF_DIR/versions.env"
# shellcheck disable=SC1091
source "$SELF_DIR/scripts/build-common.sh"
build_need docker || { echo 'Docker is required only for this maintainer rebuild path.' >&2; exit 1; }
for c in curl tar sha256sum find file readelf sort awk install python3 id; do build_need "$c"; done
OUT="${1:-$SELF_DIR/dist/native-rebuild}"
mkdir -p "$OUT"; OUT="$(CDPATH= cd -- "$OUT" && pwd -P)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/agent-env-native-rebuild.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
CACHE="$SELF_DIR/.download-cache/native-rebuild"
mkdir -p "$CACHE"
max_glibc(){ find "$1" -type f -print0 | while IFS= read -r -d '' f; do if file "$f" | grep -q ELF; then readelf --version-info "$f" 2>/dev/null || true; fi; done | grep -oE 'GLIBC_[0-9]+([.][0-9]+)+' | sort -Vu | tail -1; }
require_floor(){ local v; v="$(max_glibc "$1")"; python3 - "$v" <<'PY'
import re,sys
m=re.fullmatch(r'GLIBC_(\d+)\.(\d+)',sys.argv[1]); assert m,sys.argv[1]
assert tuple(map(int,m.groups())) <= (2,28), sys.argv[1]
PY
}
build_acquire_verified "$POSTGRES_SOURCE_URL" "$CACHE/postgresql-$POSTGRES_VERSION.tar.bz2" "$POSTGRES_SOURCE_SHA256"
build_acquire_verified "$POSTGRES_FLEX_RPM_URL" "$CACHE/$POSTGRES_FLEX_RPM_NEVRA.rpm" "$POSTGRES_FLEX_RPM_SHA256"
build_acquire_verified "$PLPGSQL_CHECK_SOURCE_URL" "$CACHE/plpgsql-check-$PLPGSQL_CHECK_VERSION.tar.gz" "$PLPGSQL_CHECK_SOURCE_SHA256"
install -m 0644 "$CACHE/postgresql-$POSTGRES_VERSION.tar.bz2" "$WORK/postgresql.tar.bz2"
install -m 0644 "$CACHE/$POSTGRES_FLEX_RPM_NEVRA.rpm" "$WORK/postgres-flex.rpm"
install -m 0644 "$CACHE/plpgsql-check-$PLPGSQL_CHECK_VERSION.tar.gz" "$WORK/plpgsql-check.tar.gz"
tar -xjf "$WORK/postgresql.tar.bz2" -C "$WORK"; tar -xzf "$WORK/plpgsql-check.tar.gz" -C "$WORK"
IMAGE="$(build_docker_image_ref "$POSTGRES_BUILD_IMAGE" "$POSTGRES_BUILD_IMAGE_SHA256")"
docker run --rm --network none \
  -e POSTGRES_FLEX_VERSION="$POSTGRES_FLEX_VERSION" \
  -e POSTGRES_FLEX_RPM_NEVRA="$POSTGRES_FLEX_RPM_NEVRA" \
  -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
  -v "$WORK:/work" "$IMAGE" bash -lc '
set -euo pipefail
restore_owner() { chown -R "$HOST_UID:$HOST_GID" /work >/dev/null 2>&1 || true; }
trap restore_owner EXIT
flex_nevra="$(rpm -qp --qf "%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n" /work/postgres-flex.rpm)"
[[ "$flex_nevra" == "$POSTGRES_FLEX_RPM_NEVRA" ]]
rpm -K /work/postgres-flex.rpm | grep -F "digests signatures OK" >/dev/null
rpm -Uvh --nodeps --noscripts /work/postgres-flex.rpm >/dev/null
[[ "$(flex --version)" == "flex $POSTGRES_FLEX_VERSION" ]]
command -v m4 >/dev/null
cd /work/postgresql-17.10
./configure --prefix=/opt/pgbuild --without-readline --without-zlib --without-icu >/dev/null
make AROPT=crsD -j2 >/dev/null
make AROPT=crsD DESTDIR=/work/pg-stage install >/dev/null
rm -rf /opt/pgbuild; cp -a /work/pg-stage/opt/pgbuild /opt/pgbuild
cd /work/plpgsql_check-2.8.11
make -j2 USE_PGXS=1 PG_CONFIG=/opt/pgbuild/bin/pg_config >/dev/null
make USE_PGXS=1 PG_CONFIG=/opt/pgbuild/bin/pg_config DESTDIR=/work/pl-stage install >/dev/null
'
STAGE="$WORK/pg-stage/opt/pgbuild"; mkdir -p "$WORK/client-payload/bin" "$WORK/client-payload/lib"
for tool in psql pg_isready createdb dropdb pgbench pg_dump pg_restore pg_dumpall pg_amcheck pg_checksums; do install -m 0755 "$STAGE/bin/$tool" "$WORK/client-payload/bin/$tool"; done
cp -a "$STAGE/lib/libpq.so"* "$WORK/client-payload/lib/"
PLSO="$(find "$WORK/pl-stage" -type f -name plpgsql_check.so -print -quit)"; mkdir -p "$WORK/plcheck-payload"
install -m 0755 "$PLSO" "$WORK/plcheck-payload/plpgsql_check.so"
install -m 0644 "$WORK/plpgsql_check-2.8.11/plpgsql_check.control" "$WORK/plcheck-payload/plpgsql_check.control"
cp "$WORK/plpgsql_check-2.8.11"/plpgsql_check--*.sql "$WORK/plcheck-payload/"; chmod 0644 "$WORK/plcheck-payload"/*.sql
require_floor "$WORK/client-payload"; require_floor "$WORK/plcheck-payload"
tar --sort=name --mtime='UTC 2026-08-20' --owner=0 --group=0 --numeric-owner -czf "$OUT/postgresql-client-17.10-linux-x64-gnu.tar.gz" -C "$WORK" client-payload
tar --sort=name --mtime='UTC 2026-08-20' --owner=0 --group=0 --numeric-owner -czf "$OUT/plpgsql-check-2.8.11-pg17-linux-x64-gnu.tar.gz" -C "$WORK" plcheck-payload
build_verify_sha256 "$OUT/postgresql-client-17.10-linux-x64-gnu.tar.gz" "$POSTGRES_CLIENT_SHA256"
build_verify_sha256 "$OUT/plpgsql-check-2.8.11-pg17-linux-x64-gnu.tar.gz" "$PLPGSQL_CHECK_SHA256"
printf 'Reproduced exact qualified payloads:\n%s\n%s\n' "$OUT/postgresql-client-17.10-linux-x64-gnu.tar.gz" "$OUT/plpgsql-check-2.8.11-pg17-linux-x64-gnu.tar.gz"
