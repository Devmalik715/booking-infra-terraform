#!/usr/bin/env bash
#
# Takes a timestamped logical backup of the local Postgres container.
#
#   ./scripts/backup.sh                  # dump into ./backups
#   ./scripts/backup.sh -o /tmp/dumps    # dump somewhere else
#   ./scripts/backup.sh -k 3             # keep only the 3 newest dumps
#
# pg_dump runs *inside* the container, so nothing has to be installed on the
# host beyond docker. The dump is written in the custom format (-Fc) because it
# is compressed, restores selectively and can be listed without restoring it.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

# .env is optional; docker-compose.yml has the same defaults baked in.
if [[ -f .env ]]; then
    # shellcheck disable=SC1091
    set -a && source .env && set +a
fi

DB_NAME="${POSTGRES_DB:-bookings}"
DB_USER="${POSTGRES_USER:-bookings_app}"
SERVICE="${DB_SERVICE:-postgres}"
BACKUP_DIR="${BACKUP_DIR:-./backups}"
KEEP="${BACKUP_KEEP:-7}"

while getopts ":o:k:h" opt; do
    case "${opt}" in
        o) BACKUP_DIR="${OPTARG}" ;;
        k) KEEP="${OPTARG}" ;;
        h) sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        \?) echo "unknown option: -${OPTARG}" >&2; exit 2 ;;
        :) echo "option -${OPTARG} needs a value" >&2; exit 2 ;;
    esac
done

# docker compose (v2) or docker-compose (v1), whichever this machine has.
if docker compose version >/dev/null 2>&1; then
    COMPOSE="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE="docker-compose"
else
    echo "ERROR: neither 'docker compose' nor 'docker-compose' is available." >&2
    exit 1
fi

# Asking the database whether it is ready beats asking docker whether a
# container exists: a container that is up but still replaying the init scripts
# is not something to dump or restore into.
if ! ${COMPOSE} exec -T "${SERVICE}" pg_isready -U "${DB_USER}" -d "${DB_NAME}" >/dev/null 2>&1; then
    echo "ERROR: cannot reach the '${SERVICE}' service. Start it with: docker compose up -d" >&2
    echo "       (if it was only just started, give the seed a few seconds to finish)" >&2
    exit 1
fi

mkdir -p "${BACKUP_DIR}"

STAMP="$(date +%Y%m%d_%H%M%S)"
DUMP_FILE="${BACKUP_DIR}/${DB_NAME}_${STAMP}.dump"

echo "==> Backing up database '${DB_NAME}' from service '${SERVICE}'"

# --no-owner / --no-privileges keep the dump portable: it can be restored as any
# role, which matters when a local dump is replayed against a different user.
${COMPOSE} exec -T "${SERVICE}" pg_dump \
    --username="${DB_USER}" \
    --dbname="${DB_NAME}" \
    --format=custom \
    --compress=6 \
    --no-owner \
    --no-privileges \
    > "${DUMP_FILE}"

# A pg_dump that exits 0 can still leave a truncated file if the pipe broke, so
# check the archive is readable before calling the backup good.
if ! pg_restore_output="$(${COMPOSE} exec -T "${SERVICE}" pg_restore --list < "${DUMP_FILE}" 2>&1)"; then
    echo "ERROR: the dump could not be read back - treating this backup as failed." >&2
    echo "${pg_restore_output}" >&2
    rm -f "${DUMP_FILE}"
    exit 1
fi

TABLE_COUNT="$(printf '%s\n' "${pg_restore_output}" | grep -c 'TABLE DATA' || true)"
SIZE="$(du -h "${DUMP_FILE}" | cut -f1)"

# Checksum so a corrupted copy is obvious later.
if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${DUMP_FILE}" > "${DUMP_FILE}.sha256"
elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "${DUMP_FILE}" > "${DUMP_FILE}.sha256"
fi

echo "    file    : ${DUMP_FILE}"
echo "    size    : ${SIZE}"
echo "    tables  : ${TABLE_COUNT} with data"
echo "    verified: archive listing is readable"

# Retention. Deliberately counted, not time-based: on a laptop the script may
# not run for days, and "keep the last N" never leaves you with zero backups.
if [[ "${KEEP}" -gt 0 ]]; then
    pruned=0
    # shellcheck disable=SC2012  # these names are generated above, no spaces or newlines in them
    while IFS= read -r old_dump; do
        [[ -z "${old_dump}" ]] && continue
        if [[ "${pruned}" -eq 0 ]]; then
            echo "==> Pruning dumps beyond the newest ${KEEP}"
        fi
        rm -f "${old_dump}" "${old_dump}.sha256"
        echo "    removed ${old_dump}"
        pruned=$((pruned + 1))
    done < <(ls -1t "${BACKUP_DIR}/${DB_NAME}"_*.dump 2>/dev/null | tail -n "+$((KEEP + 1))")
fi

echo "==> Backup complete"
