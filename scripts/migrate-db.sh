#!/usr/bin/env bash
# Run pending DB migrations against the in-cluster PostgreSQL (manual / CI helper).
#
# Usage (on VPS or with kubectl pointed at the cluster):
#   ./scripts/migrate-db.sh
#   ./scripts/migrate-db.sh down 1
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

direction="${1:-up}"
steps="${2:-}"

sync_db_migrations

MIGRATIONS_DIR="$CHART_DIR/migrations"
[ -d "$MIGRATIONS_DIR" ] || fail "migrations directory not found: $MIGRATIONS_DIR"

require_tools
require_cluster_prereqs

CM_NAME="$RELEASE-db-migrations-manual"
kubectl -n "$NAMESPACE" delete configmap "$CM_NAME" --ignore-not-found

kubectl -n "$NAMESPACE" create configmap "$CM_NAME" \
  --from-file="$MIGRATIONS_DIR"

JOB_NAME="$RELEASE-db-migrate-manual-$(date +%s)"
if [ "$direction" = "up" ]; then
  MIGRATE_CMD='migrate -path=/migrations -database "postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${DB_HOST}:${DB_PORT}/${POSTGRES_DB}?sslmode=disable" up'
elif [ "$direction" = "down" ]; then
  [ -n "$steps" ] || fail "usage: $0 down <steps>"
  MIGRATE_CMD="migrate -path=/migrations -database \"postgres://\${POSTGRES_USER}:\${POSTGRES_PASSWORD}@\${DB_HOST}:\${DB_PORT}/\${POSTGRES_DB}?sslmode=disable\" down ${steps}"
else
  fail "usage: $0 [up|down <steps>]"
fi

cat <<EOF | kubectl -n "$NAMESPACE" apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: $JOB_NAME
spec:
  backoffLimit: 2
  activeDeadlineSeconds: 600
  template:
    spec:
      restartPolicy: Never
      initContainers:
        - name: wait-postgres
          image: busybox:1.36
          command:
            - sh
            - -c
            - |
              until nc -z "\${DB_HOST}" "\${DB_PORT}"; do
                echo "waiting for postgres..."
                sleep 2
              done
          envFrom:
            - configMapRef:
                name: ${RELEASE}-runtime-env
      containers:
        - name: migrate
          image: migrate/migrate:v4.18.2
          command:
            - sh
            - -c
            - |
              $MIGRATE_CMD
          envFrom:
            - configMapRef:
                name: ${RELEASE}-runtime-env
            - secretRef:
                name: ${RELEASE}-runtime-secret
          volumeMounts:
            - name: migrations
              mountPath: /migrations
              readOnly: true
      volumes:
        - name: migrations
          configMap:
            name: $CM_NAME
EOF

kubectl -n "$NAMESPACE" wait --for=condition=complete "job/$JOB_NAME" --timeout=600s
kubectl -n "$NAMESPACE" logs "job/$JOB_NAME"
kubectl -n "$NAMESPACE" delete job "$JOB_NAME" --ignore-not-found
kubectl -n "$NAMESPACE" delete configmap "$CM_NAME" --ignore-not-found

echo "==> migrate $direction complete"
