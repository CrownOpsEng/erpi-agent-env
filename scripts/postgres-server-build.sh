#!/usr/bin/env bash
set -euo pipefail
: "${POSTGRES_VERSION:?}"
: "${POSTGRES_FLEX_VERSION:?}"
: "${POSTGRES_FLEX_RPM_NEVRA:?}"
: "${ERPI_BUILD_JOBS:?}"
: "${HOST_UID:?}"
: "${HOST_GID:?}"

restore_owner() { chown -R "$HOST_UID:$HOST_GID" /work >/dev/null 2>&1 || true; }
trap restore_owner EXIT

flex_nevra="$(rpm -qp --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' /work/postgres-flex.rpm)"
[[ "$flex_nevra" == "$POSTGRES_FLEX_RPM_NEVRA" ]] || {
  echo "Pinned PostgreSQL Flex RPM identity mismatch: $flex_nevra" >&2
  exit 1
}
rpm -K /work/postgres-flex.rpm | grep -F 'digests signatures OK' >/dev/null || {
  echo 'Pinned PostgreSQL Flex RPM signature/digest verification failed.' >&2
  exit 1
}
rpm -Uvh --nodeps --noscripts /work/postgres-flex.rpm >/dev/null
[[ "$(flex --version)" == "flex $POSTGRES_FLEX_VERSION" ]] || {
  echo 'Pinned PostgreSQL Flex executable version mismatch.' >&2
  exit 1
}
command -v m4 >/dev/null || {
  echo 'Pinned PostgreSQL build image no longer supplies m4 required by Flex.' >&2
  exit 1
}

cd "/work/postgresql-${POSTGRES_VERSION}"
./configure --prefix=/usr/local/pg-build --without-readline --without-zlib --without-icu >/dev/null
make AROPT=crsD -j"$ERPI_BUILD_JOBS" >/dev/null
make AROPT=crsD DESTDIR=/work/stage install >/dev/null
make -C contrib/amcheck AROPT=crsD -j"$ERPI_BUILD_JOBS" >/dev/null
make -C contrib/amcheck AROPT=crsD DESTDIR=/work/stage install >/dev/null
