#!/usr/bin/env bash
#
# Restores a dump into a fresh database and compares it against the source.
#
#   ./scripts/restore.sh                      newest dump -> bookings_restore_<stamp>
#   ./scripts/restore.sh path/to.dump          restore a specific dump
#   ./scripts/restore.sh -d name              choose the target database
#   ./scripts/restore.sh -d bookings --force  overwrite an existing one (asks first)

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
TARGET_DB=""
FORCE="false"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--database) TARGET_DB="$2"; shift 2 ;;
        -f|--force)    FORCE="true"; shift ;;
        -h|--help)     sed -n '2,8p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*)            echo "unknown option: $1" >&2; exit 2 ;;
        *)             DUMP_FILE="$1"; shift ;;
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

ready=0
# shellcheck disable=SC2034
for i in {1..15}; do
    if ${COMPOSE} exec -T "${SERVICE}" pg_isready -U "${DB_USER}" -d "${DB_NAME}" >/dev/null 2>&1; then
        ready=1
        break
    fi
    sleep 1
done

if [[ "${ready}" -eq 0 ]]; then
    echo "ERROR: cannot reach the '${SERVICE}' service. Start it with: docker compose up -d" >&2
    echo "       (if it was only just started, give the seed a few seconds to finish)" >&2
    exit 1
fi

if [[ -z "${DUMP_FILE:-}" ]]; then
    # shellcheck disable=SC2012
    DUMP_FILE="$(ls -1t "${BACKUP_DIR}/${DB_NAME}"_*.dump 2>/dev/null | head -n1 || true)"
    if [[ -z "${DUMP_FILE}" ]]; then
        echo "ERROR: no dump found in ${BACKUP_DIR}. Run ./scripts/backup.sh first." >&2
        exit 1
    fi
    echo "==> No dump specified, using the newest one"
fi

if [[ ! -f "${DUMP_FILE}" ]]; then
    echo "ERROR: ${DUMP_FILE} does not exist." >&2
    exit 1
fi

if [[ -z "${TARGET_DB}" ]]; then
    TARGET_DB="${DB_NAME}_restore_$(date +%Y%m%d_%H%M%S)"
fi

echo "==> Restoring ${DUMP_FILE} into database '${TARGET_DB}'"

if [[ -f "${DUMP_FILE}.sha256" ]]; then
    checksum_cmd=""
    if command -v sha256sum >/dev/null 2>&1; then
        checksum_cmd="sha256sum --check --status"
    elif command -v shasum >/dev/null 2>&1; then
        checksum_cmd="shasum -a 256 --check --status"
    fi

    if [[ -n "${checksum_cmd}" ]]; then
        if ${checksum_cmd} "${DUMP_FILE}.sha256"; then
            echo "    checksum: ok"
        else
            echo "ERROR: ${DUMP_FILE} does not match its recorded sha256." >&2
            echo "       The file is corrupt or truncated - do not restore it." >&2
            exit 1
        fi
    fi
fi

psql_run() {
    ${COMPOSE} exec -T "${SERVICE}" psql \
        --username="${DB_USER}" \
        --dbname="$1" \
        --no-psqlrc \
        --set=ON_ERROR_STOP=1 \
        --tuples-only \
        --no-align \
        --command="$2"
}

db_exists() {
    [[ "$(psql_run postgres "SELECT 1 FROM pg_database WHERE datname = '$1'")" == "1" ]]
}

if db_exists "${TARGET_DB}"; then
    if [[ "${FORCE}" != "true" ]]; then
        echo "ERROR: database '${TARGET_DB}' already exists. Pass --force to drop and recreate it." >&2
        exit 1
    fi
    read -r -p "Drop and recreate '${TARGET_DB}'? All data in it will be lost. [y/N] " reply
    if [[ ! "${reply}" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi
    echo "==> Dropping existing database '${TARGET_DB}'"
    # Existing sessions hold the database open and block the drop.
    psql_run postgres "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${TARGET_DB}' AND pid <> pg_backend_pid()" >/dev/null
    psql_run postgres "DROP DATABASE ${TARGET_DB}" >/dev/null
fi

psql_run postgres "CREATE DATABASE ${TARGET_DB} OWNER ${DB_USER}" >/dev/null
echo "    created empty database"

${COMPOSE} exec -T "${SERVICE}" pg_restore \
    --username="${DB_USER}" \
    --dbname="${TARGET_DB}" \
    --no-owner \
    --no-privileges \
    --exit-on-error \
    < "${DUMP_FILE}"

echo "    data loaded"

# pg_dump carries no planner statistics.
psql_run "${TARGET_DB}" "VACUUM ANALYZE" >/dev/null
echo "    statistics rebuilt (VACUUM ANALYZE)"

FINGERPRINT_SQL="SELECT
      (SELECT count(*) FROM hotel_bookings)
   || '|' || (SELECT count(*) FROM booking_events)
   || '|' || (SELECT coalesce(sum(amount), 0) FROM hotel_bookings)
   || '|' || (SELECT coalesce(max(created_at)::text, '-') FROM hotel_bookings)
   || '|' || (SELECT count(*) FROM pg_indexes WHERE schemaname = 'public')"

SOURCE_FP="$(psql_run "${DB_NAME}" "${FINGERPRINT_SQL}")"
TARGET_FP="$(psql_run "${TARGET_DB}" "${FINGERPRINT_SQL}")"

IFS='|' read -r s_bookings s_events s_amount s_latest s_indexes <<<"${SOURCE_FP}"
IFS='|' read -r t_bookings t_events t_amount t_latest t_indexes <<<"${TARGET_FP}"

echo ""
printf '%-18s %-28s %-28s\n' "check" "source (${DB_NAME})" "restored (${TARGET_DB})"
printf '%-18s %-28s %-28s\n' "------------------" "----------------------------" "----------------------------"
printf '%-18s %-28s %-28s\n' "hotel_bookings"  "${s_bookings}" "${t_bookings}"
printf '%-18s %-28s %-28s\n' "booking_events"  "${s_events}"   "${t_events}"
printf '%-18s %-28s %-28s\n' "sum(amount)"     "${s_amount}"   "${t_amount}"
printf '%-18s %-28s %-28s\n' "max(created_at)" "${s_latest}"   "${t_latest}"
printf '%-18s %-28s %-28s\n' "indexes"         "${s_indexes}"  "${t_indexes}"
echo ""

if [[ "${SOURCE_FP}" == "${TARGET_FP}" ]]; then
    echo "==> Restore verified: the restored database matches the source on every check."
    echo "    Inspect it with:"
    echo "      docker compose exec ${SERVICE} psql -U ${DB_USER} -d ${TARGET_DB} -c '\\dt'"
    echo "    Drop it when you are done with:"
    echo "      docker compose exec ${SERVICE} psql -U ${DB_USER} -d postgres -c 'DROP DATABASE ${TARGET_DB}'"
else
    echo "==> MISMATCH between source and restored database." >&2
    echo "    Note: this is expected if the source changed after the dump was taken." >&2
    exit 1
fi
