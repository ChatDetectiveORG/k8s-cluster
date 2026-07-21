#!/usr/bin/env bash
# Selective production deploy: helm upgrade + rollout for ONE microservice.
#
# Run on the VPS after patch-image-tag.sh updated values-k3s-images.yaml.
#
# Usage:
#   ./scripts/patch-image-tag.sh payment-service <sha>
#   ./scripts/deploy-service.sh payment-service
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

service="${1:-}"
[ -n "$service" ] || fail "usage: $0 <helm-service>"

validate_helm_service "$service"
require_tools
require_secrets_file
require_images_file
require_cluster_prereqs

helm_dependency_build
helm_render_guard
helm_upgrade_release false
rollout_deployment "$service" "${ROLLOUT_TIMEOUT:-300s}"

echo "==> selective deploy complete: $service"
