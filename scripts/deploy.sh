#!/usr/bin/env bash
# Full production deploy/upgrade of ChatDetective on a single-node k3s VPS.
#
# Run this script ON THE VPS (after SSH) from a checkout of the k8s-cluster repo:
#   ./scripts/deploy.sh
#
# For selective single-service deploys use deploy-service.sh (triggered by CI).
#
# Required files on the VPS (never committed to git):
#   $SECRETS_FILE  - filled-in copy of values-k3s-secrets.example.yaml (mode 600)
#   $IMAGES_FILE   - filled-in copy of values-k3s-images.example.yaml (pinned image tags)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_tools
require_secrets_file
require_images_file
require_cluster_prereqs

helm_dependency_build
helm_render_guard
helm_upgrade_release true

echo "==> waiting for rollouts"
for deploy in \
  api-gateway command-handler mailing-service message-sender event-loop payment-service \
  chat-export-service business-events-new business-events-edited postgresql redis
do
  rollout_deployment "$deploy" 180s
done

echo "==> done. Release status:"
helm -n "$NAMESPACE" status "$RELEASE" | head -15
