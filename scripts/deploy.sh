#!/usr/bin/env bash
# Manual production deploy/upgrade of ChatDetective on a single-node k3s VPS.
#
# Run this script ON THE VPS (after SSH) from a checkout of the k8s-cluster repo:
#   ./scripts/deploy.sh
#
# It never talks to the Kubernetes API over the internet: kubectl/helm use the local
# kubeconfig (/etc/rancher/k3s/k3s.yaml via KUBECONFIG or root's default).
#
# Required files on the VPS (never committed to git):
#   $SECRETS_FILE  - filled-in copy of values-k3s-secrets.example.yaml (mode 600)
#   $IMAGES_FILE   - filled-in copy of values-k3s-images.example.yaml (pinned image tags)
set -euo pipefail

NAMESPACE="${NAMESPACE:-chatdetective}"
RELEASE="${RELEASE:-chatdetective}"
CHART_DIR="${CHART_DIR:-$(cd "$(dirname "$0")/../helm/chatdetective-dev" && pwd)}"
SECRETS_FILE="${SECRETS_FILE:-/root/chatdetective/values-k3s-secrets.yaml}"
IMAGES_FILE="${IMAGES_FILE:-/root/chatdetective/values-k3s-images.yaml}"
HELM_TIMEOUT="${HELM_TIMEOUT:-10m}"

fail() { echo "ERROR: $*" >&2; exit 1; }

command -v helm >/dev/null || fail "helm is not installed"
command -v kubectl >/dev/null || fail "kubectl is not installed"

[ -d "$CHART_DIR" ] || fail "chart dir not found: $CHART_DIR"
[ -f "$SECRETS_FILE" ] || fail "secrets file not found: $SECRETS_FILE (copy values-k3s-secrets.example.yaml and fill it in)"
[ -f "$IMAGES_FILE" ] || fail "images file not found: $IMAGES_FILE (copy values-k3s-images.example.yaml and pin image tags)"

# The secrets file must not be world/group readable.
perm="$(stat -c '%a' "$SECRETS_FILE" 2>/dev/null || stat -f '%Lp' "$SECRETS_FILE")"
case "$perm" in
  600|400) ;;
  *) fail "secrets file $SECRETS_FILE must have mode 600 (got $perm): chmod 600 '$SECRETS_FILE'" ;;
esac

kubectl get namespace "$NAMESPACE" >/dev/null 2>&1 || kubectl create namespace "$NAMESPACE"

kubectl -n "$NAMESPACE" get secret ghcr-pull-secret >/dev/null 2>&1 \
  || fail "ghcr-pull-secret is missing in namespace $NAMESPACE (see docs/k3s-production-deploy.md, section GHCR)"

echo "==> helm dependency build"
helm dependency build "$CHART_DIR"

echo "==> rendering release (production guards run here)"
helm template "$RELEASE" "$CHART_DIR" \
  --namespace "$NAMESPACE" \
  -f "$CHART_DIR/values.yaml" \
  -f "$CHART_DIR/values-k3s-mini.yaml" \
  -f "$IMAGES_FILE" \
  -f "$SECRETS_FILE" >/dev/null

echo "==> helm upgrade --install $RELEASE"
helm upgrade --install "$RELEASE" "$CHART_DIR" \
  --namespace "$NAMESPACE" \
  --atomic \
  --timeout "$HELM_TIMEOUT" \
  -f "$CHART_DIR/values.yaml" \
  -f "$CHART_DIR/values-k3s-mini.yaml" \
  -f "$IMAGES_FILE" \
  -f "$SECRETS_FILE"

echo "==> waiting for rollouts"
for deploy in \
  api-gateway command-handler message-sender event-loop payment-service \
  chat-export-service business-events-new business-events-edited postgresql redis
do
  kubectl -n "$NAMESPACE" rollout status "deploy/$RELEASE-$deploy" --timeout=180s
done

echo "==> done. Release status:"
helm -n "$NAMESPACE" status "$RELEASE" | head -15
