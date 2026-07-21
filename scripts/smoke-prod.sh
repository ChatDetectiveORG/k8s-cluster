#!/usr/bin/env bash
# Post-deploy smoke checks (automated subset of the prod-live checklist).
#
# Optional env:
#   PROD_HOST          — ingress host, e.g. bot.example.com
#   DEPLOYED_SERVICE   — if set, also waits for that deployment rollout
#
# Usage:
#   PROD_HOST=bot.example.com ./scripts/smoke-prod.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_tools

host="${PROD_HOST:-}"
if [ -z "$host" ] && [ -f "$SECRETS_FILE" ]; then
  host="$(python3 - "$SECRETS_FILE" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r'host:\s*"([^"]+)"', text)
print(m.group(1) if m else "")
PY
)"
fi

echo "==> pod summary"
kubectl -n "$NAMESPACE" get pods

if [ -n "${DEPLOYED_SERVICE:-}" ]; then
  validate_helm_service "$DEPLOYED_SERVICE"
  echo "==> rollout status: $DEPLOYED_SERVICE"
  rollout_deployment "$DEPLOYED_SERVICE" "${ROLLOUT_TIMEOUT:-300s}"
fi

if [ -n "$host" ]; then
  echo "==> HTTP probes on https://${host}"
  curl -fsS -o /dev/null -w 'healthz: %{http_code}\n' "https://${host}/healthz"
  curl -fsS -o /dev/null -w 'readyz: %{http_code}\n' "https://${host}/readyz"
  echo "==> ingress + certificate"
  kubectl -n "$NAMESPACE" get ingress,certificate 2>/dev/null || true
else
  echo "==> PROD_HOST not set; skipping external HTTP checks" >&2
fi

if crontab -l 2>/dev/null | grep -q 'backup-postgres.sh'; then
  echo "==> backup cron: configured"
else
  echo "WARN: backup-postgres.sh not found in root crontab" >&2
fi

echo "==> smoke checks finished"
