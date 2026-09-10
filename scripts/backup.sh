#!/usr/bin/env bash
#
# Timestamped dump of the local Postgres container.
#
#   ./scripts/backup.sh              dump into ./backups
#   ./scripts/backup.sh -o /tmp      dump somewhere else
#   ./scripts/backup.sh -k 3         keep only the 3 newest dumps (0 = keep all)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

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
        h) sed -n '2,7p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        \?) echo "unknown option: -${OPTARG}" >&2; exit 2 ;;
        :) echo "option -${OPTARG} needs a value" >&2; exit 2 ;;
    esac
done

if docker compose version >/dev/null 2>&1; then
    COMPOSE="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE="docker-compose"
else
    echo "ERROR: neither 'docker compose' nor 'docker-compose' is available." >&2
    exit 1
fi

if ! ${COMPOSE} exec -T "${SERVICE}" pg_isready -U "${DB_USER}" -d "${DB_NAME}" >/dev/null 2>&1; then
    echo "ERROR: cannot reach the '${SERVICE}' service. Start it with: docker compose up -d" >&2
    echo "       (if it was only just started, give the seed a few seconds to finish)" >&2
    exit 1
fi

mkdir -p "${BACKUP_DIR}"

STAMP="$(date +%Y%m%d_%H%M%S)"
DUMP_FILE="${BACKUP_DIR}/${DB_NAME}_${STAMP}.dump"

echo "==> Backing up database '${DB_NAME}' from service '${SERVICE}'"

${COMPOSE} exec -T "${SERVICE}" pg_dump \
    --username="${DB_USER}" \
    --dbname="${DB_NAME}" \
    --format=custom \
    --compress=6 \
    --no-owner \
    --no-privileges \
    > "${DUMP_FILE}"

# pg_dump can exit 0 and still leave a truncated file if the pipe broke.
if ! pg_restore_output="$(${COMPOSE} exec -T "${SERVICE}" pg_restore --list < "${DUMP_FILE}" 2>&1)"; then
    echo "ERROR: the dump could not be read back - treating this backup as failed." >&2
    echo "${pg_restore_output}" >&2
    rm -f "${DUMP_FILE}"
    exit 1
fi

TABLE_COUNT="$(printf '%s\n' "${pg_restore_output}" | grep -c 'TABLE DATA' || true)"
SIZE="$(du -h "${DUMP_FILE}" | cut -f1)"

if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${DUMP_FILE}" > "${DUMP_FILE}.sha256"
elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "${DUMP_FILE}" > "${DUMP_FILE}.sha256"
fi

echo "    file    : ${DUMP_FILE}"
echo "    size    : ${SIZE}"
echo "    tables  : ${TABLE_COUNT} with data"
echo "    verified: archive listing is readable"

if [[ "${KEEP}" -gt 0 ]]; then
    pruned=0
    # shellcheck disable=SC2012
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
