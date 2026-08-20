#!/usr/bin/env bash
set -euo pipefail
umask 022

ROOT="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck disable=SC1091
source "$ROOT/versions.env"

OUT="${1:-$ROOT/dist/postgres-server-qualification}"
mkdir -p "$OUT"
OUT="$(CDPATH='' cd -- "$OUT" && pwd -P)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/magnet-postgres-server-qualification.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing qualification command: $1" >&2; exit 1; }; }
for cmd in docker curl tar gzip sha256sum find file readelf sort awk install grep sed python3 cp; do need "$cmd"; done

grep -q 'GNU tar' < <(tar --version) || { echo 'GNU tar is required.' >&2; exit 1; }

PG_URL="https://ftp.postgresql.org/pub/source/v${POSTGRES_VERSION}/postgresql-${POSTGRES_VERSION}.tar.bz2"
PG_SHA="078a03516dcdbdb705fecaf415ea3d13a956c589e46f09fed68a06fb00598c90"
IMAGE="quay.io/pypa/manylinux_2_28_x86_64@sha256:0c87ccb5996dab6c3b7612ee4fda7b80c4ab3c44a86c2541e4a872afdf4f131b"
SOURCE="$WORK/postgresql-${POSTGRES_VERSION}.tar.bz2"

sha() { sha256sum "$1" | awk '{print $1}'; }
fetch() {
  curl --fail --location --proto '=https' --tlsv1.2 --retry 4 --retry-all-errors --connect-timeout 20 -o "$2" "$1"
  [[ "$(sha "$2")" == "$3" ]] || { echo "SHA-256 mismatch for $2" >&2; exit 1; }
}
max_glibc() {
  find "$1" -type f -print0 | while IFS= read -r -d '' f; do
    if file "$f" | grep -q ELF; then readelf --version-info "$f" 2>/dev/null || true; fi
  done | grep -oE 'GLIBC_[0-9]+([.][0-9]+)+' | sort -Vu | tail -1
}
require_floor() {
  local value
  value="$(max_glibc "$1")"
  python3 - "$value" <<'PY'
import re,sys
m=re.fullmatch(r'GLIBC_(\d+)\.(\d+)',sys.argv[1]); assert m,sys.argv[1]
assert tuple(map(int,m.groups())) <= (2,28), sys.argv[1]
PY
  printf '%s\n' "$value"
}

fetch "$PG_URL" "$SOURCE" "$PG_SHA"
docker pull "$IMAGE" >/dev/null

build_once() {
  local label="$1" work="$WORK/$1" stage payload archive
  mkdir -p "$work"
  tar -xjf "$SOURCE" -C "$work"
  docker run --rm -v "$work:/work" "$IMAGE" bash -lc '
    set -euo pipefail
    dnf -y install flex >/dev/null
    cd /work/postgresql-17.10
    ./configure --prefix=/opt/pgbuild --without-readline --without-zlib --without-icu >/dev/null
    make -j2 >/dev/null
    make DESTDIR=/work/pg-stage install >/dev/null
    make -C contrib/amcheck -j2 >/dev/null
    make -C contrib/amcheck DESTDIR=/work/pg-stage install >/dev/null
  '

  stage="$work/pg-stage/opt/pgbuild"
  payload="$work/server-payload"
  mkdir -p "$payload/bin" "$payload/lib/postgresql" "$payload/share/postgresql"
  for tool in postgres initdb pg_ctl; do install -m 0755 "$stage/bin/$tool" "$payload/bin/$tool"; done
  cp -a "$stage/lib/postgresql/." "$payload/lib/postgresql/"
  cp -a "$stage/share/postgresql/." "$payload/share/postgresql/"
  install -m 0644 "$work/postgresql-${POSTGRES_VERSION}/COPYRIGHT" "$payload/COPYRIGHT"

  mapfile -t modules < <(find "$payload/lib/postgresql" -maxdepth 1 -type f -name '*.so' -printf '%f\n' | LC_ALL=C sort)
  [[ "${modules[*]}" == 'amcheck.so plpgsql.so' ]] || {
    printf 'Unexpected PostgreSQL server module set: %s\n' "${modules[*]}" >&2
    exit 1
  }

  local abs_link=0 link target
  while IFS= read -r -d '' link; do
    target="$(readlink "$link")"
    if [[ "$target" == /* ]]; then echo "Absolute symlink: $link -> $target" >&2; abs_link=1; fi
  done < <(find "$payload" -type l -print0)
  (( abs_link == 0 )) || exit 1

  local writable
  writable="$(find "$payload" -type f -perm /022 -print -quit)"
  [[ -z "$writable" ]] || { echo "Writable immutable server file: $writable" >&2; exit 1; }

  local needed="$work/needed-libraries.txt"
  : > "$needed"
  while IFS= read -r -d '' f; do
    if file "$f" | grep -q ELF; then
      readelf -d "$f" 2>/dev/null | sed -n 's/.*Shared library: \[\([^]]*\)\].*/\1/p' >> "$needed" || true
    fi
  done < <(find "$payload" -type f -print0)
  LC_ALL=C sort -u -o "$needed" "$needed"
  if grep -Eq '^(libssl|libcrypto|libicu|libxml2|libxslt|libz\.so|liblzma|libreadline|libuuid|liblz4|libzstd)' "$needed"; then
    echo 'Lean server unexpectedly depends on an excluded third-party runtime library:' >&2
    cat "$needed" >&2
    exit 1
  fi

  require_floor "$payload" > "$work/max-glibc.txt"

  archive="$WORK/postgres-server-${label}.tar.gz"
  tar --sort=name --format=gnu --numeric-owner --owner=0 --group=0 \
    --mtime="$ARCHIVE_MTIME" -cf - -C "$work" server-payload | gzip -n > "$archive"
  printf '%s\n' "$archive"
}

FIRST="$(build_once first)"
SECOND="$(build_once second)"
FIRST_SHA="$(sha "$FIRST")"
SECOND_SHA="$(sha "$SECOND")"
[[ "$FIRST_SHA" == "$SECOND_SHA" ]] || {
  echo 'Independent PostgreSQL server builds are not byte-for-byte reproducible.' >&2
  echo "first  $FIRST_SHA" >&2
  echo "second $SECOND_SHA" >&2
  exit 1
}

FINAL="$OUT/postgres-server-${POSTGRES_VERSION}-linux-x64-gnu.tar.gz"
cp "$FIRST" "$FINAL"
(cd "$OUT" && sha256sum "$(basename -- "$FINAL")") > "$FINAL.sha256"

# Integrate the candidate with the exact source-controlled client, pgTAP, and
# plpgsql_check payloads that the final runtime builder will use.
TEST="$WORK/Relocated server – spaces and unicode/数据库/qualification"
mkdir -p "$TEST/server" "$TEST/client" "$TEST/plcheck"
tar -xzf "$FINAL" -C "$TEST/server"
tar -xzf "$ROOT/vendor/database/postgresql-client-${POSTGRES_VERSION}-linux-x64-gnu.tar.gz" -C "$TEST/client"
tar -xzf "$ROOT/vendor/database/plpgsql-check-${PLPGSQL_CHECK_VERSION}-pg17-linux-x64-gnu.tar.gz" -C "$TEST/plcheck"
SERVER="$TEST/server/server-payload"
CLIENT="$TEST/client/client-payload"
PLCHECK="$TEST/plcheck/plcheck-payload"
install -m 0644 "$ROOT/vendor/pgtap/pgtap.control" "$SERVER/share/postgresql/extension/pgtap.control"
install -m 0644 "$ROOT/vendor/pgtap/pgtap--${PGTAP_VERSION}.sql" "$SERVER/share/postgresql/extension/pgtap--${PGTAP_VERSION}.sql"
install -m 0644 "$PLCHECK/plpgsql_check.control" "$SERVER/share/postgresql/extension/plpgsql_check.control"
install -m 0644 "$PLCHECK/plpgsql_check--2.8.sql" "$SERVER/share/postgresql/extension/plpgsql_check--2.8.sql"
install -m 0755 "$PLCHECK/plpgsql_check.so" "$SERVER/lib/postgresql/plpgsql_check.so"

export LD_LIBRARY_PATH="$CLIENT/lib"
PORT="$(python3 - <<'PY'
import socket
s=socket.socket(); s.bind(('127.0.0.1',0)); print(s.getsockname()[1]); s.close()
PY
)"
DATA="$TEST/data"
LOG="$TEST/postgres.log"
"$SERVER/bin/initdb" -D "$DATA" --encoding=UTF8 --locale=C.utf8 --data-checksums --username=postgres --auth-local=trust --auth-host=trust >/dev/null
cat >> "$DATA/postgresql.conf" <<CFG
listen_addresses = '127.0.0.1'
port = $PORT
unix_socket_directories = ''
jit = off
timezone = 'UTC'
CFG
started=0
cleanup_server() {
  if (( started )); then "$SERVER/bin/pg_ctl" -D "$DATA" -m fast -w stop >/dev/null 2>&1 || true; fi
}
trap 'cleanup_server; rm -rf "$WORK"' EXIT
"$SERVER/bin/pg_ctl" -D "$DATA" -l "$LOG" -w start >/dev/null
started=1
export PGHOST=127.0.0.1 PGPORT="$PORT" PGDATABASE=postgres PGUSER=postgres
"$CLIENT/bin/pg_isready" -q
"$CLIENT/bin/psql" -X -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
CREATE EXTENSION pgtap;
CREATE EXTENSION plpgsql_check;
CREATE EXTENSION amcheck;
CREATE OR REPLACE FUNCTION qualification_good() RETURNS integer LANGUAGE plpgsql AS $$ BEGIN RETURN 1; END $$;
SELECT count(*) FROM plpgsql_check_function_tb('qualification_good()');
SQL
"$CLIENT/bin/psql" -X -Atc "select count(*) from plpgsql_check_function_tb('qualification_good()')" | grep -Fx 0 >/dev/null
"$CLIENT/bin/pg_amcheck" --install-missing --database=postgres >/dev/null
"$CLIENT/bin/pgbench" -i -s 1 postgres >/dev/null
"$CLIENT/bin/pgbench" -c 2 -j 1 -t 2 postgres >/dev/null
"$SERVER/bin/pg_ctl" -D "$DATA" -m fast -w stop >/dev/null
started=0
"$CLIENT/bin/pg_checksums" --check -D "$DATA" >/dev/null
python3 - "$PORT" <<'PY'
import socket,sys
s=socket.socket(); s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1); s.bind(('127.0.0.1',int(sys.argv[1]))); s.close()
PY

FIRST_GLIBC="$(cat "$WORK/first/max-glibc.txt")"
SECOND_GLIBC="$(cat "$WORK/second/max-glibc.txt")"
[[ "$FIRST_GLIBC" == "$SECOND_GLIBC" ]]
cat > "$OUT/qualification.txt" <<REPORT
status=qualified
postgres_version=${POSTGRES_VERSION}
source_url=${PG_URL}
source_sha256=${PG_SHA}
builder_image=${IMAGE}
configure=--prefix=/opt/pgbuild --without-readline --without-zlib --without-icu
archive=$(basename -- "$FINAL")
archive_sha256=${FIRST_SHA}
reproducible_sha256=${SECOND_SHA}
max_glibc=${FIRST_GLIBC}
modules=amcheck.so plpgsql.so
integration=source-controlled client + pgTAP + plpgsql_check + amcheck + pg_amcheck + pgbench + checksums
REPORT

echo "Qualified PostgreSQL server payload: $FINAL"
echo "SHA-256: $FIRST_SHA"
echo "Max GLIBC symbol: $FIRST_GLIBC"
