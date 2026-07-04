#!/usr/bin/env bash
# Daily PostgreSQL backup for AIFA production stack.
# Schedule: 0 3 * * * /apps/aifa-infra/scripts/backup-db.sh
set -euo pipefail

COMPOSE_DIR="$(dirname "$0")/../compose"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/aifa}"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"

mkdir -p "$BACKUP_DIR"

cd "$COMPOSE_DIR"
docker compose -f docker-compose.prod.yml exec -T postgres \
  pg_dump -U "${POSTGRES_USER:-aifa}" -d "${POSTGRES_DB:-aifa_ecommerce}" \
  | gzip > "${BACKUP_DIR}/aifa-${TIMESTAMP}.sql.gz"

echo "Backup written: ${BACKUP_DIR}/aifa-${TIMESTAMP}.sql.gz"

# Keep last 14 backups
ls -1t "${BACKUP_DIR}"/aifa-*.sql.gz 2>/dev/null | tail -n +15 | xargs -r rm --
