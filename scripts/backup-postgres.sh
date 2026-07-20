#!/usr/bin/env bash
# PostgreSQL backup for the ChatDetective k3s deployment. Run ON THE VPS.
#
#   ./scripts/backup-postgres.sh
#
# Creates a gzip-compressed SQL dump (pg_dump --clean --if-exists) in $BACKUP_DIR and
# removes backups older than $RETENTION_DAYS. Add to root's crontab, e.g. daily at 03:30:
#   30 3 * * * /root/k8s-cluster/scripts/backup-postgres.sh >> /var/log/chatdetective-backup.log 2>&1
set -euo pipefail

NAMESPACE="${NAMESPACE:-chatdetective}"
RELEASE="${RELEASE:-chatdetective}"
BACKUP_DIR="${BACKUP_DIR:-/root/chatdetective/backups}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"
DB_USER="${DB_USER:-chatdetective}"
DB_NAME="${DB_NAME:-chatdetective}"

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

timestamp="$(date +%Y%m%d-%H%M%S)"
backup_file="$BACKUP_DIR/chatdetective-$timestamp.sql.gz"

echo "==> dumping $DB_NAME to $backup_file"
kubectl -n "$NAMESPACE" exec "deploy/$RELEASE-postgresql" -- \
  pg_dump --clean --if-exists -U "$DB_USER" "$DB_NAME" | gzip > "$backup_file"
chmod 600 "$backup_file"

# A dump of an empty database is still a few hundred bytes; anything smaller means failure.
size="$(wc -c < "$backup_file")"
[ "$size" -gt 200 ] || { echo "ERROR: backup file suspiciously small ($size bytes)" >&2; exit 1; }

echo "==> pruning backups older than $RETENTION_DAYS days"
find "$BACKUP_DIR" -name 'chatdetective-*.sql.gz' -type f -mtime +"$RETENTION_DAYS" -print -delete

echo "==> done: $backup_file ($size bytes)"
