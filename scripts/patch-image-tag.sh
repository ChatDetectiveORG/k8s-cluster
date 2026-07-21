#!/usr/bin/env bash
# Patch a single service image tag in values-k3s-images.yaml (selective deploy).
#
# Usage:
#   ./scripts/patch-image-tag.sh api-gateway <40-char-commit-sha>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

service="${1:-}"
sha="${2:-}"

[ -n "$service" ] || fail "usage: $0 <helm-service> <commit-sha>"
[ -n "$sha" ] || fail "usage: $0 <helm-service> <commit-sha>"

validate_helm_service "$service"
validate_sha "$sha"
require_images_file

python3 - "$IMAGES_FILE" "$service" "$sha" <<'PY'
import re
import sys

path, key, sha = sys.argv[1:4]
block = (
    f"{key}:\n"
    f"  image:\n"
    f'    tag: "{sha}"\n'
    f"    pullPolicy: IfNotPresent\n\n"
)

with open(path, encoding="utf-8") as fh:
    text = fh.read()

pattern = (
    rf"{re.escape(key)}:\n"
    r"  image:\n"
    r'    tag: "[^"]*"(?:[^\n]*)?\n'
    r"    pullPolicy: IfNotPresent\n\n?"
)

if re.search(pattern, text):
    text = re.sub(pattern, block, text, count=1)
else:
    if not text.endswith("\n"):
        text += "\n"
    text += "\n" + block

with open(path, "w", encoding="utf-8") as fh:
    fh.write(text)
PY

echo "==> patched $IMAGES_FILE: $service -> $sha"
