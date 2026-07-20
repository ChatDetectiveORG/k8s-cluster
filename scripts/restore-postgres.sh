#!/usr/bin/env bash
# PostgreSQL restore for the ChatDetective k3s deployment. Run ON THE VPS.
#
#   ./scripts/restore-postgres.sh /root/chatdetective/backups/chatdetective-YYYYmmdd-HHMMSS.sql.gz
#
# DESTRUCTIVE: the dump was taken with --clean --if-exists, so restoring drops and
# recreates every table in the target database. The script requires an explicit
# confirmation phrase before doing anything.
set -euo pipefail

NAMESPACE="${NAMESPACE:-chatdetective}"
RELEASE="${RELEASE:-chatdetective}"
DB_USER="${DB_USER:-chatdetective}"
DB_NAME="${DB_NAME:-chatdetective}"

backup_file="${1:-}"
[ -n "$backup_file" ] || { echo "usage: $0 <backup-file.sql.gz>" >&2; exit 1; }
[ -f "$backup_file" ] || { echo "ERROR: backup file not found: $backup_file" >&2; exit 1; }

echo "About to RESTORE database '$DB_NAME' in namespace '$NAMESPACE' from:"
echo "  $backup_file"
echo
echo "This DROPS and recreates all tables. Consider scaling app deployments to 0 first:"
echo "  kubectl -n $NAMESPACE scale deploy -l app.kubernetes.io/instance=$RELEASE --replicas=0"
echo
printf "Type exactly 'restore %s' to continue: " "$DB_NAME"
read -r answer
[ "$answer" = "restore $DB_NAME" ] || { echo "Aborted."; exit 1; }

echo "==> restoring"
gunzip -c "$backup_file" | kubectl -n "$NAMESPACE" exec -i "deploy/$RELEASE-postgresql" -- \
  psql -v ON_ERROR_STOP=1 -U "$DB_USER" "$DB_NAME"

echo "==> done. Verify row counts, then scale the app back up if you scaled it down."
