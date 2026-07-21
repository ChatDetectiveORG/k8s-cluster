#!/usr/bin/env bash
# Shared production deploy settings for ChatDetective k3s scripts.
set -euo pipefail

NAMESPACE="${NAMESPACE:-chatdetective}"
RELEASE="${RELEASE:-chatdetective}"
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_REPO_ROOT="$(cd "$_LIB_DIR/../.." && pwd)"
CHART_DIR="${CHART_DIR:-${_REPO_ROOT}/helm/chatdetective-dev}"
SECRETS_FILE="${SECRETS_FILE:-/root/chatdetective/values-k3s-secrets.yaml}"
IMAGES_FILE="${IMAGES_FILE:-/root/chatdetective/values-k3s-images.yaml}"
HELM_TIMEOUT="${HELM_TIMEOUT:-10m}"
KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"

# Helm values keys for the eight application microservices.
VALID_HELM_SERVICES=(
  api-gateway
  command-handler
  message-sender
  event-loop
  payment-service
  chat-export-service
  business-events-new
  business-events-edited
)

fail() { echo "ERROR: $*" >&2; exit 1; }

export KUBECONFIG

require_tools() {
  command -v helm >/dev/null || fail "helm is not installed"
  command -v kubectl >/dev/null || fail "kubectl is not installed"
}

validate_helm_service() {
  local service="$1"
  local s
  for s in "${VALID_HELM_SERVICES[@]}"; do
    [ "$s" = "$service" ] && return 0
  done
  fail "unknown helm service '$service' (expected one of: ${VALID_HELM_SERVICES[*]})"
}

validate_sha() {
  local sha="$1"
  [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || fail "invalid image tag SHA: $sha"
}

require_secrets_file() {
  [ -f "$SECRETS_FILE" ] || fail "secrets file not found: $SECRETS_FILE"
  local perm
  perm="$(stat -c '%a' "$SECRETS_FILE" 2>/dev/null || stat -f '%Lp' "$SECRETS_FILE")"
  case "$perm" in
    600|400) ;;
    *) fail "secrets file $SECRETS_FILE must have mode 600 (got $perm)" ;;
  esac
}

require_images_file() {
  [ -f "$IMAGES_FILE" ] || fail "images file not found: $IMAGES_FILE (bootstrap with fetch-image-tags.sh or first deploy)"
}

require_cluster_prereqs() {
  kubectl get namespace "$NAMESPACE" >/dev/null 2>&1 || kubectl create namespace "$NAMESPACE"
  kubectl -n "$NAMESPACE" get secret ghcr-pull-secret >/dev/null 2>&1 \
    || fail "ghcr-pull-secret is missing in namespace $NAMESPACE"
}

helm_dependency_build() {
  echo "==> helm dependency build"
  helm dependency build "$CHART_DIR"
}

helm_render_guard() {
  echo "==> rendering release (production guards)"
  helm template "$RELEASE" "$CHART_DIR" \
    --namespace "$NAMESPACE" \
    -f "$CHART_DIR/values.yaml" \
    -f "$CHART_DIR/values-k3s-mini.yaml" \
    -f "$IMAGES_FILE" \
    -f "$SECRETS_FILE" >/dev/null
}

sync_db_migrations() {
  "$_LIB_DIR/sync-db-migrations.sh"
}

helm_upgrade_release() {
  local atomic="${1:-false}"
  sync_db_migrations
  echo "==> helm upgrade --install $RELEASE (atomic=$atomic)"
  if [ "$atomic" = "true" ]; then
    helm upgrade --install "$RELEASE" "$CHART_DIR" \
      --namespace "$NAMESPACE" \
      --atomic \
      --timeout "$HELM_TIMEOUT" \
      -f "$CHART_DIR/values.yaml" \
      -f "$CHART_DIR/values-k3s-mini.yaml" \
      -f "$IMAGES_FILE" \
      -f "$SECRETS_FILE"
  else
    helm upgrade --install "$RELEASE" "$CHART_DIR" \
      --namespace "$NAMESPACE" \
      --timeout "$HELM_TIMEOUT" \
      -f "$CHART_DIR/values.yaml" \
      -f "$CHART_DIR/values-k3s-mini.yaml" \
      -f "$IMAGES_FILE" \
      -f "$SECRETS_FILE"
  fi
}

rollout_deployment() {
  local service="$1"
  local timeout="${2:-300s}"
  kubectl -n "$NAMESPACE" rollout status "deploy/$RELEASE-$service" --timeout="$timeout"
}
