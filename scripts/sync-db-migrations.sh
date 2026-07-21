#!/usr/bin/env bash
# Copy SQL migrations from the shared module into the Helm chart (embedded ConfigMap source).
#
# Run from anywhere in the monorepo before committing k8s-cluster, or automatically
# from deploy scripts when a sibling shared/ checkout exists.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
K8S_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MONO_ROOT="$(cd "$K8S_ROOT/.." && pwd)"
SRC="${DB_MIGRATIONS_SRC:-$MONO_ROOT/shared/migrations}"
DEST="$K8S_ROOT/helm/chatdetective-dev/migrations"

if [ ! -d "$SRC" ]; then
  echo "sync-db-migrations: source not found ($SRC), using committed chart migrations"
  exit 0
fi

mkdir -p "$DEST"
rsync -a --delete "$SRC/" "$DEST/"
echo "sync-db-migrations: $SRC -> $DEST"
